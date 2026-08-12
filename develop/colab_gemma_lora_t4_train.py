# ================================
# 📦 必要ライブラリのインストール
# ================================
!pip install -q transformers accelerate peft datasets bitsandbytes
!huggingface-cli login

# ================================
# ⚙️ モデルとトークナイザの設定（4bit量子化）
# ================================
from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
from peft import LoraConfig, get_peft_model
import torch

model_name = "google/gemma-2-2b-jpn-it"

# トークナイザ読み込み
tokenizer = AutoTokenizer.from_pretrained(model_name)
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token

# 4bit量子化設定
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_compute_dtype=torch.float16,
    bnb_4bit_use_double_quant=True,
    bnb_4bit_quant_type="nf4"
)

# モデル読み込み（T4対応！）
model = AutoModelForCausalLM.from_pretrained(
    model_name,
    quantization_config=bnb_config,
    device_map="auto"
)

# LoRA設定
lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type="CAUSAL_LM"
)

model = get_peft_model(model, lora_config)
model.print_trainable_parameters()

# ================================
# 📄 データ読み込み・前処理
# ================================
from datasets import load_dataset

# サンプルデータ（自分の knowledge.txt に置き換えてOK）
dataset = load_dataset("text", data_files={"train": "knowledge.txt"})

def preprocess_function(examples):
    encodings = tokenizer(
        examples["text"],
        truncation=True,
        max_length=256,  # メモリ節約のため短く設定
        padding="max_length"
    )
    encodings["labels"] = encodings["input_ids"].copy()
    return encodings

tokenized_dataset = dataset.map(
    preprocess_function,
    batched=True,
    remove_columns=["text"]
)

# ================================
# 🛠️ トレーニング設定（T4向け）
# ================================
from transformers import TrainingArguments, Trainer, DataCollatorForLanguageModeling

training_args = TrainingArguments(
    output_dir="./lora_results",
    num_train_epochs=1,
    per_device_train_batch_size=1,
    gradient_accumulation_steps=8,
    learning_rate=2e-4,
    fp16=True,
    save_steps=100,
    save_total_limit=1,
    logging_steps=10,
    remove_unused_columns=False,
    label_names=["labels"]
)

data_collator = DataCollatorForLanguageModeling(
    tokenizer=tokenizer,
    mlm=False
)

trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=tokenized_dataset["train"],
    data_collator=data_collator
)

# ================================
# 🚀 トレーニング開始 & 保存
# ================================
trainer.train()

model.save_pretrained("./lora_gemma")
tokenizer.save_pretrained("./lora_gemma")
print("✅ LoRAファインチューニングが完了しました！")

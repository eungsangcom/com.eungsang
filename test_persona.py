from unsloth import FastLanguageModel

# EXAONE 커스텀 클래스가 get/set_input_embeddings를 구현 안 해서 나는 오류 우회
# (merge_and_export.py와 동일한 패치)
import torch.nn as nn
from transformers.modeling_utils import PreTrainedModel
_orig_get_input_embeddings = PreTrainedModel.get_input_embeddings
_orig_set_input_embeddings = PreTrainedModel.set_input_embeddings

def _find_embedding_path(module):
    for name, child in module.named_modules():
        if isinstance(child, nn.Embedding):
            return name
    return None

def _patched_get_input_embeddings(self):
    try:
        return _orig_get_input_embeddings(self)
    except NotImplementedError:
        path = _find_embedding_path(self)
        if path is None:
            raise
        mod = self
        for part in path.split("."):
            mod = getattr(mod, part)
        return mod

def _patched_set_input_embeddings(self, value):
    try:
        return _orig_set_input_embeddings(self, value)
    except NotImplementedError:
        path = _find_embedding_path(self)
        if path is None:
            raise
        *parents, leaf = path.split(".")
        mod = self
        for part in parents:
            mod = getattr(mod, part)
        setattr(mod, leaf, value)

PreTrainedModel.get_input_embeddings = _patched_get_input_embeddings
PreTrainedModel.set_input_embeddings = _patched_set_input_embeddings

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="eungsang/apps/exaone_hologram/models/exaone-hologram-merged",
    max_seq_length=1024,
    load_in_4bit=False,
    trust_remote_code=True,
)
FastLanguageModel.for_inference(model)

messages = [{"role": "user", "content": "당신은 누구고, 이은상님의 포트폴리오에 대해 뭘 알고 있나요?"}]
inputs = tokenizer.apply_chat_template(messages, tokenize=True, add_generation_prompt=True, return_tensors="pt").to("cuda")
out = model.generate(inputs, max_new_tokens=200)
print(tokenizer.decode(out[0][inputs.shape[1]:], skip_special_tokens=True))
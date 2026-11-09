"""Optional loopback table service. Downloads pinned weights ONLY when explicitly run.
Install torch, transformers==5.22.2, accelerate, Pillow. Not started by the app.
CUDA GPU required for this measured configuration; Apple Silicon has not been validated.
"""
import base64, io, json
from http.server import BaseHTTPRequestHandler, HTTPServer

REVISION = '132c45f52c0a26ed5a6b2f6bd8e3985794cc27dd'

def main():
    import torch
    from PIL import Image
    from transformers import AutoProcessor, AutoModelForImageTextToText
    model_id = 'PaddlePaddle/PaddleOCR-VL-1.6'
    if not torch.cuda.is_available():
        raise SystemExit('This measured service requires CUDA. No CPU/MPS performance claim is made.')
    processor = AutoProcessor.from_pretrained(model_id, revision=REVISION)
    model = AutoModelForImageTextToText.from_pretrained(model_id, revision=REVISION, torch_dtype=torch.bfloat16, use_safetensors=True).to('cuda').eval()
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass  # Never log document images or request bodies.
        def do_POST(self):
            try:
                if self.path != '/table': raise ValueError('Unsupported route')
                n = int(self.headers.get('Content-Length', '0'))
                if not 0 < n <= 5_500_000: raise ValueError('Image exceeds request limit')
                data_url = json.loads(self.rfile.read(n))['image']
                prefix = 'data:image/jpeg;base64,'
                if not data_url.startswith(prefix): raise ValueError('JPEG required')
                image = Image.open(io.BytesIO(base64.b64decode(data_url[len(prefix):], validate=True)))
                if image.width * image.height > 16_000_000: raise ValueError('Image dimensions exceed limit')
                image = image.convert('RGB')
                messages = [{'role':'user','content':[{'type':'image','image':image},{'type':'text','text':'Table Recognition:'}]}]
                inputs = processor.apply_chat_template(messages, tokenize=True, add_generation_prompt=True, return_dict=True, return_tensors='pt').to('cuda')
                with torch.inference_mode(): output = model.generate(**inputs, max_new_tokens=4096, do_sample=False)
                ids = output[0, inputs['input_ids'].shape[1]:]
                if len(ids) >= 4096: raise ValueError('Token limit reached; partial table discarded')
                reply = {'text':processor.decode(ids, skip_special_tokens=True),'model_revision':REVISION}
                status = 200
            except Exception:
                reply = {'error':'Table inference failed or exceeded its bounds; partial output discarded'}; status = 422
            body = json.dumps(reply).encode()
            self.send_response(status); self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    print('PaddleOCR loopback service: http://127.0.0.1:8766/table', flush=True)
    HTTPServer(('127.0.0.1',8766),Handler).serve_forever()

if __name__ == '__main__': main()

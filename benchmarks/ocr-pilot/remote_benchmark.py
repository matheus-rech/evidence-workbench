import base64,gc,hashlib,io,json,os,platform,resource,time,zlib,urllib.request
import torch,transformers,psutil
from PIL import Image
from transformers import AutoProcessor,AutoModelForImageTextToText
payload=json.loads(os.environ['BENCHMARK_INPUTS'])
results=[]
print('BENCHMARK_ENV '+json.dumps({'torch':torch.__version__,'transformers':transformers.__version__,'python':platform.python_version(),'gpu':torch.cuda.get_device_name(0)}),flush=True)
models=[('glm-ocr','zai-org/GLM-OCR','2e85a62840ccac27daa451df36c736c4636b8628'),('paddleocr-vl-1.6','PaddlePaddle/PaddleOCR-VL-1.6','132c45f52c0a26ed5a6b2f6bd8e3985794cc27dd')]
for engine,repo,revision in models:
 start=time.perf_counter()
 processor=AutoProcessor.from_pretrained(repo,revision=revision)
 model=AutoModelForImageTextToText.from_pretrained(repo,revision=revision,torch_dtype=torch.bfloat16,use_safetensors=True).to('cuda').eval()
 load_seconds=time.perf_counter()-start
 for sample in payload:
  imagebytes=urllib.request.urlopen(sample['remote_url'],timeout=120).read();assert hashlib.sha256(imagebytes).hexdigest()==sample['image_sha256']
  image=Image.open(io.BytesIO(imagebytes)).convert('RGB')
  for repeat in range(2):
   start=time.perf_counter();torch.cuda.reset_peak_memory_stats();record={'engine':engine,'model':repo,'revision':revision,'sample':sample['id'],'repeat':repeat,'image_sha256':sample['image_sha256'],'load_seconds':load_seconds,'hardware':torch.cuda.get_device_name(0)}
   try:
    prompt=('Table Recognition:' if sample['task']=='table' else 'Text Recognition:') if engine=='glm-ocr' else ('Table Recognition:' if sample['task']=='table' else 'OCR:')
    messages=[{'role':'user','content':[{'type':'image','image':image},{'type':'text','text':prompt}]}]
    inputs=processor.apply_chat_template(messages,tokenize=True,add_generation_prompt=True,return_dict=True,return_tensors='pt').to('cuda')
    with torch.inference_mode():output=model.generate(**inputs,max_new_tokens=4096,do_sample=False)
    torch.cuda.synchronize();token_ids=output[0,inputs['input_ids'].shape[1]:]
    record['text']=processor.decode(token_ids,skip_special_tokens=True);record['output_tokens']=len(token_ids);record['hit_token_cap']=len(token_ids)>=4096
    del inputs,output,token_ids
   except Exception as exc:record['error']=str(exc)
   record['elapsed_seconds']=time.perf_counter()-start;record['gpu_peak_allocated_bytes']=torch.cuda.max_memory_allocated();record['process_rss_bytes']=psutil.Process().memory_info().rss;record['process_peak_rss_bytes']=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*1024
   results.append(record)
   print('OCR_SAMPLE_B64:'+base64.b64encode(zlib.compress(json.dumps(record).encode())).decode(),flush=True)
 del model,processor;gc.collect();torch.cuda.empty_cache()
print('BENCHMARK_FINISHED',len(results),flush=True)

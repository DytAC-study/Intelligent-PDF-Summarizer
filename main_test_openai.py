import os
from azure.core.credentials import AzureKeyCredential
from azure.ai.openai import OpenAIClient
from azure.core.credentials import AzureKeyCredential


# 从 local.settings.json 加载环境变量（或你自己 export 环境变量）
endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
key = os.environ.get("AZURE_OPENAI_KEY")
deployment = os.environ.get("CHAT_MODEL_DEPLOYMENT_NAME")

client = OpenAIClient(endpoint=endpoint, credential=AzureKeyCredential(key))

response = client.get_chat_completions(
    deployment_id=deployment,
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Summarize what Azure Durable Functions are."}
    ]
)

print("=== Response ===")
print(response.choices[0].message["content"])

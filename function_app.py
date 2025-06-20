import logging
import os
import json
import time
from datetime import datetime

import azure.functions as func
import azure.durable_functions as df
from azure.storage.blob import BlobServiceClient
from azure.core.credentials import AzureKeyCredential
from azure.ai.formrecognizer import DocumentAnalysisClient

# Durable Functions app and Blob client setup
my_app = df.DFApp(http_auth_level=func.AuthLevel.ANONYMOUS)
blob_service_client = BlobServiceClient.from_connection_string(
    os.environ["BLOB_STORAGE_ENDPOINT"]
)

def mock_summary(text: str) -> str:
    """
    Local mock to replace Azure OpenAI. 
    Returns a fixed sample summary.
    """
    return "This is a mock summary of the PDF document."

# 1) Blob trigger: start orchestration when a PDF lands in 'input'
@my_app.blob_trigger(arg_name="myblob", path="input", connection="BLOB_STORAGE_ENDPOINT")
@my_app.durable_client_input(client_name="client")
async def blob_trigger(myblob: func.InputStream, client):
    logging.info(
        f"Processing blob: Name={myblob.name}, Size={myblob.length} bytes"
    )
    blob_name = myblob.name.split("/", 1)[1]
    await client.start_new("process_document", client_input=blob_name)

# 2) Orchestrator: define workflow steps
@my_app.orchestration_trigger(context_name="context")
def process_document(context):
    blob_name: str = context.get_input()

    retry_opts = df.RetryOptions(
        first_retry_interval_in_milliseconds=5000,
        max_number_of_attempts=3
    )

    # 2.1 Extract text via Form Recognizer
    text = yield context.call_activity_with_retry(
        "analyze_pdf", retry_opts, blob_name
    )

    # 2.2 Generate summary (mocked locally)
    summary_obj = yield context.call_activity_with_retry(
        "summarize_text", retry_opts, text
    )

    # 2.3 Write out the summary
    result = yield context.call_activity_with_retry(
        "write_doc", retry_opts,
        { "blobName": blob_name, "summary": summary_obj }
    )

    logging.info(f"Summary saved as: {result}")
    return result

# 3) Activity: pull PDF, run Form Recognizer
@my_app.activity_trigger(input_name="blobName")
def analyze_pdf(blobName: str):
    logging.info("In analyze_pdf activity")
    container = blob_service_client.get_container_client("input")
    blob = container.get_blob_client(blobName).download_blob().read()

    endpoint = os.environ["COGNITIVE_SERVICES_ENDPOINT"]
    key = os.environ["COGNITIVE_SERVICES_KEY"]
    document_analysis_client = DocumentAnalysisClient(
        endpoint, AzureKeyCredential(key)
    )

    poller = document_analysis_client.begin_analyze_document(
        "prebuilt-layout", document=blob, locale="en-US"
    )
    pages = poller.result().pages

    # concatenate all lines
    text = "".join(line.content for page in pages for line in page.lines)
    return text

# 4) Activity: mock summary instead of Azure OpenAI
@my_app.activity_trigger(input_name="results")
def summarize_text(results: str):
    logging.info("In summarize_text (mock) activity")
    content = mock_summary(results)
    logging.info(f"Mock summary: {content}")
    # mirror original response JSON shape
    return { "content": content }

# 5) Activity: write summary to output container
@my_app.activity_trigger(input_name="results")
def write_doc(results: dict):
    logging.info("In write_doc activity")
    container = blob_service_client.get_container_client("output")

    # build a timestamped filename
    base_name = results["blobName"].rsplit(".", 1)[0]
    timestamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    file_name = f"{base_name}-{timestamp}.txt"

    container.upload_blob(name=file_name, data=results["summary"]["content"])
    return file_name

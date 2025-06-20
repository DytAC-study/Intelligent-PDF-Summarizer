Video：https://youtu.be/M0Kr5P3fQ7k

# Intelligent PDF Summarizer

This sample demonstrates building an end-to-end intelligent PDF summarizer using Azure Durable Functions, Azure Storage, and Azure Cognitive Services (Form Recognizer). The orchestrator ensures each step runs in order, preserving state and enabling retries without duplicating costly service calls.

## Architecture Overview

1. **Blob Upload:** PDFs are uploaded to the `input` container in Azure Blob Storage.
2. **Orchestration Trigger:** A Durable Function is triggered by the blob upload event.
3. **Text Extraction:** Activity function `analyze_pdf` uses Form Recognizer to extract text from the PDF.
4. **Summarization:** Activity function `summarize_text` generates a summary. In local development, this service is **mocked** (returns a fixed sample summary); in production it can call Azure OpenAI.
5. **Result Storage:** Activity function `write_doc` writes the summary to the `output` container.

### Detailed Workflow

1. **Upload & Trigger:** When a PDF lands in `input`, the blob trigger passes the blob name to the Durable orchestrator.
2. **Text Extraction Activity:** `analyze_pdf` downloads the PDF, submits it to Form Recognizer, and concatenates all detected lines into a single text string.
3. **Summarization Activity:** `summarize_text` receives the raw text. Locally it calls `mock_summary(text)` which returns a placeholder summary. In Azure, this activity can be bound to Azure OpenAI to perform real summarization.
4. **Write Output Activity:** `write_doc` takes the summary object, constructs a timestamped filename, and uploads a `.txt` file to `output`.
5. **Idempotency & Retries:** The orchestrator tracks each step’s output; on failure it retries activities without duplicating API calls or output files.

## Project Structure

```
/ (repo root)
├─ azure.yaml                # Azure Developer CLI configuration
├─ infra/
│   └─ main.bicep             # Bicep template for resources (Function App, Storage, Form Recognizer, etc.)
├─ app/
│   └─ durable-function.bicep # Dedicated module for Function App definition
├─ function_app.py           # Durable Functions code (orchestrator + activities)
├─ requirements.txt          # Python dependencies
├─ local.settings.json       # Local configuration (excluded from source control)
├─ media/architecture_v2.png  # Architecture diagram
├─ media/code.png            # Orchestration code snippet
└─ README.md                 # This documentation
```

### Key Bicep Highlights (`infra/main.bicep`)

```bicep
param location string = 'canadacentral'
param functionSkuName string = 'Y1'
param functionSkuTier string = 'Dynamic'
param documentIntelligenceSkuName string
param documentIntelligenceServiceName string

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = { ... }

module appServicePlan './core/host/appserviceplan.bicep' = { ... }
module durableFunction './app/durable-function.bicep' = {
  params: {
    appServicePlanId: appServicePlan.outputs.id
    documentIntelligenceEndpoint: documentIntelligence.outputs.endpoint
    // no VNet integration for Consumption plan
  }
}

module storage './core/storage/storage-account.bicep' = { ... }
module documentIntelligence 'br/public:avm/res/cognitive-services/account:0.5.4' = { ... }
```

## Prerequisites

- Azure subscription (e.g. Azure for Students)
- Azure Functions Core Tools
- Python 3.9+
- Azurite (for local storage emulation)
- Form Recognizer resource

## Local Setup

1. Copy `.env.example` to `local.settings.json` and fill in your values:

   ```json
   {
     "Values": {
       "AzureWebJobsStorage": "UseDevelopmentStorage=true",
       "FUNCTIONS_WORKER_RUNTIME": "python",
       "BLOB_STORAGE_ENDPOINT": "<connection-string>",
       "COGNITIVE_SERVICES_ENDPOINT": "<form-recognizer-endpoint>",
       "COGNITIVE_SERVICES_KEY": "<form-recognizer-key>"
     }
   }
   ```

2. Create and activate a virtual environment:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. Start Azurite:

   ```bash
   azurite --silent --location ./azurite
   ```

4. Create `input` and `output` containers:

   ```bash
   az storage container create -n input --connection-string "UseDevelopmentStorage=true"
   az storage container create -n output --connection-string "UseDevelopmentStorage=true"
   ```

5. Run functions locally:

   ```bash
   func start --verbose
   ```

## Deploy to Azure

Use Azure Developer CLI (azd):

```bash
azd up \
  --environment <env-name> \
  --subscription <subscription-id> \
  --location canadacentral
```

This provisions resources via Bicep and deploys your code.

## Using the App

- Upload a PDF to the **input** container in your Azure Storage account.

- The orchestrator runs and outputs a summary file in the **output** container.

- Monitor logs:

  ```bash
  azd logs functionapp --follow
  ```

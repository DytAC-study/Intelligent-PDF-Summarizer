**Video Link:** https://youtu.be/iJu6RmTxjR4

description: This end-to-end sample shows how implement an intelligent PDF summarizer using Durable Functions. 
page_type: sample
products:

- azure-functions
- azure
urlFragment: durable-func-pdf-summarizer
languages:
- python
- bicep
- azdeveloper



# Intelligent PDF Summarizer
The purpose of this sample application is to demonstrate how Durable Functions can be leveraged to create intelligent applications, particularly in a document processing scenario. Order and durability are key here because the results from one activity are passed to the next. Also, calls to services like Cognitive Service or Azure Open AI can be costly and should not be repeated in the event of failures.

This sample integrates various Azure services, including Azure Durable Functions, Azure Storage, Azure Cognitive Services, and Azure Open AI.

The application showcases how PDFs can be ingested and intelligently scanned to determine their content.

![Architecture Diagram](./media/architecture_v2.png)

The application's workflow is as follows:
1.	PDFs are uploaded to a blob storage input container.
2.	A durable function is triggered upon blob upload.
- - Downloads the blob (PDF).
- - Utilizes the Azure Cognitive Service Form Recognizer endpoint to extract the text from the PDF.
- - Sends the extracted text to Azure Open AI to analyze and determine the content of the PDF.
- - Save the summary results from Azure Open AI to a new file and upload it to the output blob container.

Below, you will find the instructions to set up and run this app locally..

## Prerequsites
- [Create an active Azure subscription](https://learn.microsoft.com/en-us/azure/guides/developer/azure-developer-guide#understanding-accounts-subscriptions-and-billing).
- [Install the latest Azure Functions Core Tools to use the CLI](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local)
- Python 3.9 or greater
- Access permissions to [create Azure OpenAI resources and to deploy models](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/role-based-access-control).
- [Start and configure an Azurite storage emulator for local storage](https://learn.microsoft.com/azure/storage/common/storage-use-azurite).

## local.settings.json
You will need to configure a `local.settings.json` file at the root of the repo that looks similar to the below. Make sure to replace the placeholders with your specific values.

```json
{
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "BLOB_STORAGE_ENDPOINT": "<BLOB-STORAGE-ENDPOINT>",
    "COGNITIVE_SERVICES_ENDPOINT": "<COGNITIVE-SERVICE-ENDPOINT>",
    "AZURE_OPENAI_ENDPOINT": "AZURE-OPEN-AI-ENDPOINT>",
    "AZURE_OPENAI_KEY": "<AZURE-OPEN-AI-KEY>",
    "CHAT_MODEL_DEPLOYMENT_NAME": "<AZURE-OPEN-AI-MODEL>"
  }
}
```

## Running the app locally
1. Start Azurite: Begin by starting Azurite, the local Azure Storage emulator.

2. Install the Requirements: Open your terminal and run the following command to install the necessary packages:

```bash
python3 -m pip install -r requirements.txt
```
3. Create two containers in your storage account. One called `input` and the other called `output`. 

4. Start the Function App: Start the function app to run the application locally.

```bash
func start --verbose
```

5. Upload PDFs to the `input` container. That will execute the blob storage trigger in your Durable Function.

6. After several seconds, your appliation should have finished the orchestrations. Switch to the `output` container and notice that the PDFs have been summarized as new files. 

>Note: The summaries may be truncated based on token limit from Azure Open AI. This is intentional as a way to reduce costs. 

## Inspect the code
This app leverages Durable Functions to orchestrate the application workflow. By using Durable Functions, there's no need for additional infrastructure like queues and state stores to manage task coordination and durability, which significantly reduces the complexity for developers. 

Take a look at the code snippet below, the `process_document` defines the entire workflow, which consists of a series of steps (activities) that need to be scheduled in sequence. Coordination is key, as the output of one activity is passed as an input to the next. Additionally, Durable Functions handle durability and retries, which ensure that if a failure occurs, such as a transient error or an issue with a dependent service, the workflow can recover gracefully.

![Orchestration Code](./media/code.png)

## Deploy the app to Azure

Use the [Azure Developer CLI (`azd`)](https://aka.ms/azd) to easily deploy the app. 

1. In the root of the project, run the following command to provision and deploy the app:

    ```bash
    azd up
    ```

1. When prompted, provide:
   - A name for your [Azure Developer CLI environment](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/faq#what-is-an-environment-name).
   - The Azure subscription you'd like to use.
   - The Azure location to use.

Once the azd up command finishes, the app will have successfully provisioned and deployed. 

# Using the app
To use the app, simply upload a PDF to the Blob Storage `input` container. Once the PDF is transferred, it will be processed using document intelligence and Azure OpenAI. The resulting summary will be saved to a new file and uploaded to the `output` container.



## Development & Deployment Challenges Encountered

During the development and deployment of this project, several technical challenges were encountered across different environments (Windows, WSL, macOS). These issues, primarily related to Azure service configuration and `azd` deployment, are documented below.

### Issue 1: Azure OpenAI `DeploymentNotFound` Error

**Error Message Example:**

```
[2025-06-19T01:56:55.766Z] System.Private.CoreLib: Exception while executing function: Functions.summarize_text. Azure.AI.OpenAI: HTTP 404 (DeploymentNotFound)
[2025-06-19T01:56:55.766Z] The API deployment for this resource does not exist. If you created the deployment within the last 5 minutes, please wait a moment and try again.
```

**Description:** When the `summarize_text` activity function attempted to call the Azure OpenAI service, a `DeploymentNotFound` error was received. This occurred despite confirming that the `gpt-35-turbo` model was successfully deployed within the Azure OpenAI resource in the Azure portal.

**Attempted Solutions:**

1. **Deployment Name Verification:** Verified that the `CHAT_MODEL_DEPLOYMENT_NAME` (set to `gpt-35-turbo` in `local.settings.json`) exactly matched the deployment name in the Azure OpenAI Studio, including case sensitivity.
2. **Endpoint Correction:** Identified a subtle mismatch in the `AZURE_OPENAI_ENDPOINT` value in `local.settings.json` compared to the actual endpoint displayed in the Azure OpenAI Studio (e.g., `.openai.azure.com` vs. `.cognitiveservices.azure.com`). The `AZURE_OPENAI_ENDPOINT` was corrected to precisely match the Azure portal's specified endpoint, `https://du000-mc2hi9wo-eastus2.cognitiveservices.azure.com/`.

### Issue 2: `azd` Deployment Failure due to `SubscriptionIsOverQuotaForSku`

**Error Message Example:**

```
ERROR: error executing step command 'provision': deployment failed: error deploying infrastructure: validating deployment to subscription:
Validation Error Details:
InvalidTemplateDeployment: The template deployment '...' is not valid according to the validation procedure.
SubscriptionIsOverQuotaForSku: This region has quota of 0 ElasticPremium instances for your subscription.. Try selecting different region or SKU.
InsufficientQuota: Insufficient quota. Cannot create/update/move resource 'cog-v3klbwazi73gq'.
```

**Description:** Upon running `azd up` to provision and deploy Azure resources, the process failed with a "quota exceeded" error, specifically indicating "quota of 0 ElasticPremium instances" in the targeted region.

**Attempted Solutions:**

1. **Environment Consistency:** The issue persisted across various development environments, including Windows, WSL, and macOS, suggesting a core configuration or Azure subscription limitation rather than an environment-specific problem.
2. **Region Selection Constraint:** During the `azd up` prompt for selecting an Azure region, "Canada Central" (the preferred region where most existing services are located) was not available as an option. Deployments attempted in other selectable regions (e.g., `East US 2`) consistently resulted in the `ElasticPremium` quota error.
3. **Subscription Type Limitation:** Further investigation strongly indicated that the "Azure for Students" subscription has inherent restrictions on deploying high-tier SKUs like `ElasticPremium`, leading to a default quota of zero for such instances.

### Issue 3: `azd` Command Not Found

**Error Message Example:**

Bash

```
zsh: command not found: azd
```

**Description:** Initially, attempts to execute the `azd` command from the terminal resulted in a "command not found" error.

**Attempted Solutions:**

1. **Initial Script Installation Attempt:** An attempt to install `azd` via `curl -fsSL https://aka.ms/azd/install.sh | bash` failed because the `aka.ms` shortlink resolved to an HTML page instead of the expected installation script.
2. **Corrected Homebrew Installation:** The issue was resolved on macOS by correctly leveraging Homebrew: first by tapping the Azure `azd` repository (`brew tap azure/azd`), and then performing the installation (`brew install azd`).

## Current Status

While the `azd` command installation and the Azure OpenAI Endpoint configuration issues have been successfully resolved, the **core deployment challenge related to the `ElasticPremium` SKU quota remains unresolved.** This prevents the project's Azure infrastructure from being successfully provisioned and deployed.

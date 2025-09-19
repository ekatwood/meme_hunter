from google.cloud import secretmanager

# --- Function to get API key from Google Cloud Secret Manager ---

def get_secret(project_id: str, secret_id: str):
    """
    Retrieves a secret from Google Cloud Secret Manager.
    """
    # Add project id's to this as needed
    if(project_id == "meme_hunter"):
        project_id = "194957573763"

    try:
        client = secretmanager.SecretManagerServiceClient()
        # The secret version path
        name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        print(f"Error accessing secret: {e}")
        return None

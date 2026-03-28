# kagglelink

Turn any Kaggle notebook into an SSH-accessible server. One command. Free GPUs.

## Overview

KaggleLink establishes a secure SSH tunnel to your Kaggle notebook, giving you full terminal access to Kaggle's free GPU resources. Use `screen`, `tmux`, run background jobs, transfer files with `rsync`—treat it like your own remote server.

> **Note:** Kaggle now offers native VS Code Remote support. KaggleLink focuses on **SSH terminal access** for workflows that require a real shell: session persistence, scripting, and direct server management.

![](https://github.com/user-attachments/assets/db4454ff-5545-4094-adeb-47b74ab0c33a)

## Getting Started

### Requirements

To use KaggleLink, you need:

1.  **Tailscale Auth Key**: Create a reusable or ephemeral auth key in your Tailscale admin console. KaggleLink uses it to attach the Kaggle notebook to your tailnet.
2.  **Local Tailscale Client**: Your local machine needs Tailscale installed and signed in to the same tailnet so you can SSH directly to the Kaggle node.
3.  **Public SSH Key URL**: KaggleLink still provisions `authorized_keys` on the notebook for compatibility with a standard SSH server. Host your public key somewhere accessible over HTTPS, such as a public GitHub raw URL.

### Quick Setup (on Kaggle)

Execute the following one-line command in a Kaggle notebook cell. This script installs Tailscale, configures SSH, and joins your Kaggle instance to your tailnet.

```bash
!curl -sS https://raw.githubusercontent.com/ingbunga/kagglelink/main/setup.sh | bash -s -- -k <public_key_url> -a <tailscale_auth_key>
```

> [!NOTE]
> Replace `<public_key_url>` with the URL of your public SSH key file and `<tailscale_auth_key>` with your Tailscale auth key.

Wait for the setup to complete. On success, the notebook logs will show the assigned Tailscale hostname, DNS name, and IPv4 address you can use from your local machine.

> [!TIP]
> **Avoiding Session Timeouts**: Kaggle's interactive notebook sessions have idle timeouts. For long-running remote development, use the **"Save & Run All"** feature by clicking the **Save Version** button (top right) and selecting "Save". This runs your notebook as a background job, avoiding timeout interruptions. You can still retrieve the Tailscale hostname and IP from the log viewer afterward.

#### How to set up your public SSH key?

1.  **Generate an SSH key pair** on your local machine (if you haven't already). Use a descriptive filename, for example:

    ```bash
    ssh-keygen -t rsa -b 4096 -C "kaggle_remote_ssh" -f ~/.ssh/kaggle_rsa
    ```

2.  **Upload your public key** (`~/.ssh/kaggle_rsa.pub`) to a public GitHub repository or a similar public file hosting service.
3.  **Obtain the Raw URL**: Navigate to your uploaded public key file in your repository and click the "Raw" button.

    ![](https://private-user-images.githubusercontent.com/140616004/444039100-ec9a884c-1c97-4be6-bd6d-03ac5dd16de7.png?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjU0NjQyMzMsIm5iZiI6MTc2NTQ2MzkzMywicGF0aCI6Ii8xNDA2MTYwMDQvNDQ0MDM5MTAwLWVjOWE4ODRjLTFjOTctNGJlNi1iZDZkLTAzYWM1ZGQxNmRlNy5wbmc_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUxMjExJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MTIxMVQxNDM4NTNaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT04YjZiY2M1OWRiMDUzYWZiMDUwODUzMjg2NDA4ZTU5NDAxZTM3YWU3ZGJmMDRlMjFiZjA0YmFmOGJlNTJmNzg1JlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.wDGsBk1CyVVAWFLSGh8wRldUbz2hiAOzw6t3Zf39K5A)

    Copy the URL from your browser's address bar. It typically looks like `https://raw.githubusercontent.com/<username>/<repo_name>/refs/heads/main/<file_path>`.

#### How to get your Tailscale auth key?

1.  Open the Tailscale admin console for your tailnet.
2.  Create an auth key for the notebook.
3.  If you want the Kaggle node to disappear automatically after shutdown, prefer an **ephemeral** key.
4.  Keep the key secret and pass it through Kaggle Secrets or a notebook environment variable when possible.

### Advanced: Environment Variables

For automated pipelines or power users, you can configure KaggleLink using environment variables instead of CLI flags.

| Variable | CLI Equivalent | Description |
|----------|----------------|-------------|
| `KAGGLELINK_KEYS_URL` | `-k` | URL to your public SSH key |
| `KAGGLELINK_AUTH_KEY` | `-a` | Your Tailscale auth key |
| `KAGGLELINK_TOKEN` | `-t` | Legacy alias for the Tailscale auth key |

> [!NOTE]
> CLI arguments (`-k`, `-a`) always override environment variables if both are present.

#### Setting Environment Variables in Kaggle

The most secure way to pass these credentials is using **Kaggle Secrets**.

1.  Add your secrets in the Kaggle notebook sidebar (**Add-ons** -> **Secrets**).
2.  Use the following Python snippet in a cell *before* running the setup script:

```python
from kaggle_secrets import UserSecretsClient
import os

user_secrets = UserSecretsClient()

# Set environment variables from secrets
# Ensure you have added 'KAGGLELINK_AUTH_KEY' and 'KAGGLELINK_KEYS_URL' to your secrets
os.environ['KAGGLELINK_AUTH_KEY'] = user_secrets.get_secret("KAGGLELINK_AUTH_KEY")

# You can also set the URL directly if it's public and not stored as a secret
os.environ['KAGGLELINK_KEYS_URL'] = "https://raw.githubusercontent.com/your/repo/main/key.pub"
```

Once the environment variables are set, you can run the setup script without arguments:

```bash
!curl -sS https://raw.githubusercontent.com/ingbunga/kagglelink/main/setup.sh | bash
```

## Usage

After completing the Kaggle setup, your Kaggle instance is attached to your tailnet. The script prints the node hostname, DNS name, and Tailscale IPv4 address.

### Client Setup (on your Local Machine)

1.  **Install Tailscale locally** and sign in to the same tailnet you used for the Kaggle auth key.
2.  **Find the node identity** from the Kaggle notebook output.
    You will usually get both:

    - a MagicDNS hostname such as `kagglelink-abc123.your-tailnet.ts.net`
    - a Tailscale IPv4 address such as `100.x.y.z`

3.  **Connect with SSH**:

    ```bash
    ssh root@kagglelink-abc123.your-tailnet.ts.net
    ```

    If MagicDNS is unavailable in your tailnet, use the Tailscale IPv4 address instead:

    ```bash
    ssh root@100.x.y.z
    ```

    KaggleLink enables Tailscale SSH when the node comes up, so the standard `ssh` command works once both machines are on the same tailnet.

### SSH Connection

Connect to your Kaggle instance via its Tailscale hostname or IP:

```bash
ssh root@kagglelink-abc123.your-tailnet.ts.net
```

> [!NOTE]
> On tailnets with the default Tailscale SSH policy, connecting to your own device as `root` is allowed after you opt the node into Tailscale SSH.

#### SSH Configuration

To simplify future connections, add the following configuration to your `~/.ssh/config` file:

```
Host Kaggle
    HostName kagglelink-abc123.your-tailnet.ts.net
    User root
```

With this configuration, you can simply use `ssh Kaggle` to connect.

### File Transfer with Rsync

Transfer files between your local machine and Kaggle instance using `rsync`:

```bash
# From local to remote
rsync -avz <path_to_local_file> root@kagglelink-abc123.your-tailnet.ts.net:<remote_destination_path>
# or if you have your SSH config set up (see above)
rsync -avz <path_to_local_file> Kaggle:<remote_destination_path>

# From remote to local
rsync -avz root@kagglelink-abc123.your-tailnet.ts.net:<path_to_remote_file> <local_destination_path>
# or if you have your SSH config set up (see above)
rsync -avz Kaggle:<path_to_remote_file> <local_destination_path>
```

## Contributing

We welcome contributions to KaggleLink! If you're interested in improving this project, please follow these steps:

1.  **Fork the repository**.
2.  **Create a new branch** for your feature or bug fix (`git checkout -b feature/your-feature-name` or `bugfix/issue-description`).
3.  **Make your changes**, adhering to the existing coding style and standards.
4.  **Write and run tests** to ensure your changes work as expected and don't introduce regressions.
5.  **Commit your changes** with clear and concise commit messages.
6.  **Push your branch** to your forked repository.
7.  **Open a Pull Request** to the main branch, providing a detailed description of your changes.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

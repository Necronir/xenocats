import json
import os
import subprocess
import sys
import urllib.request

MODEL_NAME = "qwen2.5-coder:1.5b"
OLLAMA_URL = "http://localhost:11434/api/chat"

def get_commit_message(diff_text: str) -> str:
    prompt = (
        "You are an expert Git commit message generator. Analyze the following git diff and "
        "write ONLY a single-line conventional commit message (e.g. feat(scope): subject, fix: subject, chore: subject). "
        "Do NOT output markdown, backticks, quotes, or conversational explanations. Output ONLY the commit message header."
    )
    
    # Cap diff to 8000 characters to ensure sub-second response
    if len(diff_text) > 8000:
        diff_text = diff_text[:8000] + "\n... [diff truncated]"

    payload = {
        "model": MODEL_NAME,
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": f"Git Diff:\n{diff_text}"}
        ],
        "stream": False,
        "options": {
            "num_predict": 60,
            "temperature": 0.2
        }
    }

    try:
        req = urllib.request.Request(
            OLLAMA_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.loads(response.read().decode("utf-8"))
            msg = result.get("message", {}).get("content", "").strip()
            # Clean up backticks or quotes if model added any
            msg = msg.strip("`'\" \r\n")
            # If model generated multiple lines, keep only the first line
            lines = [l.strip() for l in msg.splitlines() if l.strip()]
            return lines[0] if lines else "chore: update codebase"
    except Exception as e:
        return f"# Error contacting Ollama: {e}"

def main():
    # Filter out literal '%1', '%2', '%3' if user typed them into TortoiseGit settings
    args = [a for a in sys.argv[1:] if not a.startswith("%")]
    if len(args) < 2:
        return 0

    message_file = args[1]
    repo_dir = args[2] if len(args) > 2 and os.path.isdir(args[2]) else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    os.chdir(repo_dir)

    # 1. Check if anything is staged
    staged = subprocess.run(["git", "diff", "--cached", "--quiet"])
    if staged.returncode == 0:
        # Nothing is staged yet: stage modified tracked files
        subprocess.run(["git", "add", "-u"])

    # 2. Get the staged diff
    diff_proc = subprocess.run(["git", "diff", "--cached"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    diff_text = diff_proc.stdout.strip()

    if not diff_text:
        return 0

    # 3. Generate commit message via Ollama
    commit_msg = get_commit_message(diff_text)

    # 4. Write message to TortoiseGit's message file
    with open(message_file, "w", encoding="utf-8") as f:
        f.write(commit_msg + "\n")

    return 0

if __name__ == "__main__":
    sys.exit(main())

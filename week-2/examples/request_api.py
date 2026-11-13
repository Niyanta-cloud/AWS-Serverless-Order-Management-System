"""Send a Cognito-token-authenticated request to the OrderFlow API (stdlib only)."""
import argparse
import json
import sys
import urllib.error
import urllib.request


def main():
    # COMMAND-LINE INPUT
    # Read the HTTP method, API URL, and optional JSON request body.
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("method", choices=["GET", "POST", "PATCH", "DELETE"])
    parser.add_argument("url", help="Full API URL, including path and query string")
    parser.add_argument("--token", required=True, help="Cognito ID token for the signed-in customer")
    body_group = parser.add_mutually_exclusive_group()
    body_group.add_argument("--body", help="Raw JSON body")
    body_group.add_argument("--body-file", help="Read JSON body from a UTF-8 file")
    body_group.add_argument("--body-stdin", action="store_true",
                            help="Read the JSON body from standard input")
    args = parser.parse_args()

    # REQUEST BODY
    # Accept JSON directly, from a file, or piped from PowerShell stdin.
    body = args.body
    if args.body_file:
        with open(args.body_file, "r", encoding="utf-8") as source:
            body = source.read()
    elif args.body_stdin:
        raw_body = sys.stdin.buffer.read()
        if raw_body.startswith((b"\xff\xfe", b"\xfe\xff")):
            body = raw_body.decode("utf-16")
        elif b"\x00" in raw_body:
            body = raw_body.decode("utf-16-le")
        else:
            body = raw_body.decode("utf-8-sig")
    payload = body.encode("utf-8") if body else b""
    # COGNITO AUTHENTICATION
    # API Gateway validates this token; AWS account credentials are not used for API calls.
    http_request = urllib.request.Request(
        args.url,
        data=payload or None,
        headers={"Content-Type": "application/json", "Authorization": args.token},
        method=args.method,
    )
    # SEND REQUEST AND SHOW RESULT
    # Send HTTPS request and print the HTTP status plus the JSON response/error.
    try:
        with urllib.request.urlopen(http_request, timeout=30) as response:
            print(f"HTTP {response.status}")
            text = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        print(f"HTTP {error.code}")
        text = error.read().decode("utf-8")
        print(text)
        sys.exit(1)
    try:
        print(json.dumps(json.loads(text), indent=2))
    except json.JSONDecodeError:
        print(text)


if __name__ == "__main__":
    main()

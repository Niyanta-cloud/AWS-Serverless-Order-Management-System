"""Send a SigV4-signed request to the OrderFlow API (stdlib + boto3/botocore).

This is a local CLI client, not a Lambda function. It uses the selected AWS CLI
profile to sign API Gateway requests; API Gateway then checks IAM invoke access.
"""
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest


def main():
    # COMMAND-LINE INPUT
    # Read the HTTP method, API URL, and optional JSON request body.
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("method", choices=["GET", "POST", "PATCH", "DELETE"])
    parser.add_argument("url", help="Full API URL, including path and query string")
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
    # AWS CLIENT IDENTITY
    # boto3 loads credentials and region from AWS_PROFILE / the AWS CLI profile.
    session = boto3.Session()
    credentials = session.get_credentials()
    if credentials is None:
        parser.error("No AWS credentials found; configure the AWS CLI or AWS_PROFILE")
    credentials = credentials.get_frozen_credentials()
    region = session.region_name
    if not region:
        parser.error("No AWS region configured; set AWS_DEFAULT_REGION or configure a region")

    # SIGV4 REQUEST SIGNING
    # Sign for the execute-api service; API Gateway uses IAM to authorize this caller.
    request = AWSRequest(method=args.method, url=args.url, data=payload,
                         headers={"Content-Type": "application/json"})
    SigV4Auth(credentials, "execute-api", region).add_auth(request)
    prepared = request.prepare()
    http_request = urllib.request.Request(prepared.url, data=payload or None,
                                          headers=dict(prepared.headers), method=args.method)
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

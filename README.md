# WhatsApp Text for IRIS

[English](README.md) | [简体中文](README.zh-CN.md)

Receive WhatsApp Business text messages in an InterSystems IRIS production and send a configurable acknowledgement. Six ObjectScript classes provide the REST webhook, message type, business service, business operation, Graph HTTP adapter and example production. IRIS handles subscription verification, HMAC-SHA256 validation, event filtering and delivery. Python is used only by the local HTTP test client and simulated Graph endpoint.

## Run the local demonstration

Install Docker and obtain the IRIS for Health Community 2026.2 image, then run the following command from the project root. To use a different compatible image, set `IRIS_IMAGE`.

```sh
./tests/local-check.sh
```

The script starts an isolated container with external networking disabled and removes it on exit. It compiles the ObjectScript classes, registers the test REST application, starts a disposable production, and sends HTTP requests through the IRIS Web Gateway. It uses only synthetic credentials and phone numbers. No Python packages are installed.

The test covers valid and invalid challenges, invalid or missing signatures, malformed JSON, media and status notifications, other business numbers, and request size limits. A signed batch containing two Chinese texts is delivered twice, followed by a third text. The three distinct messages traverse the actual IRIS queue and outbound HTTP adapter. A loopback Graph server checks the destination path, recipient and reply body. Finally the script stops the production and checks that a new callback receives HTTP 503.

```text
PASS: ObjectScript REST, 5 signed texts, 3 distinct Graph replies, stopped production -> 503
```

## Install in IRIS

1. Use a dedicated interoperability-enabled namespace, a configured InterSystems Web Gateway and an instance where this project can own the global web application path `/wa-text`. With InterSystems Package Manager (IPM) 0.10.10, mount the repository at `/app` and load it from the IRIS terminal in the target namespace.

   ```objectscript
   zpm "load /app"
   ```

   IPM compiles the six `WaText` classes and configures the REST application. If your configured IPM registry already contains this package, use `zpm "install whatsapp-text-iris 1.0.0"` in the same namespace. For a manual installation, import the classes with `do $system.OBJ.LoadDir("/app/src","ck",,1)` and create the application in step 3.

2. Set these secrets and identifiers in the environment of the IRIS instance before startup. The webhook and operation workers must see the values.

   | Variable | Purpose |
   |---|---|
   | `WA_VERIFY_TOKEN` | Private token entered in Meta's subscription configuration |
   | `WA_APP_SECRET` | Meta application secret for signing webhook bodies |
   | `WA_PHONE_ID` | Numeric business phone **ID**, used to filter notifications |
   | `WA_ACCESS_TOKEN` | WhatsApp access token permitted to send from this business number |

3. In **System Administration → Security → Applications → Web Applications**, check the IPM-created `/wa-text` application or create it for a manual install. Set the namespace to the production namespace, the dispatch class to `WaText.Webhook`, authentication to unauthenticated (Meta signs POSTs), and static file serving to disabled. IPM assigns the target namespace’s globals database role to requests on this application. For a manual install, assign that role under **Application Roles**. If your mappings use additional databases, check that the application can execute the classes and queue messages there.
4. Route `/wa-text/webhook` through your Web Gateway and publish this path via HTTPS for real Meta callbacks. Pass the raw body and `X-Hub-Signature-256` unchanged. Set up access logs to omit query strings because subscription verification includes a private token. A reverse proxy can map an existing public `/webhook` to the internal `/wa-text/webhook`.
5. Configure an outbound IRIS TLS client profile with a trusted CA bundle and server-certificate verification set to **Required**. In the Management Portal, open `WaText.Production` and select **WhatsApp Reply**. Set adapter **TLSConfig** to the profile, **PhoneId** to the same numeric ID as `WA_PHONE_ID`, and **GraphVersion** to a version supported by your Meta app. Set operation **ReplyText** to customize the acknowledgement, apply the configuration and start the production.
6. In Meta's WhatsApp settings, enter your public callback URL and the same verification token. Subscribe to the WhatsApp Business Account's `messages` field. Check the app's subscription to your account and authorize the recipient for your test number.

## Follow a message

Send a text from an allowed phone to the business test number. In IRIS Message Viewer, inspect the session from **WhatsApp Input** to **WhatsApp Reply**. It contains the incoming Meta message ID, sender and text. With default settings the phone should receive **Thanks, your text reached IRIS.** A Graph message ID confirms acceptance; verify delivery on the phone. The local demonstration exercises the REST and production components with a simulated Graph endpoint. Live phone delivery requires a configured Meta account.

`WaText.Webhook` authenticates raw bytes before JSON decoding. It verifies the entire batch, selects text events for the configured business number, and returns HTTP 200 after IRIS queues all selected texts. If queuing fails partway, Meta can retry the batch after HTTP 503. The operation serializes deliveries for each inbound message ID and persists its receipt before the external call. Completed receipts suppress repeats. An uncertain or failed send leaves a pending receipt and an error in the production log. After verifying that Graph did not accept the send, an operator can clear that one pending receipt in the production namespace and resubmit the message. Retain receipts throughout Meta's redelivery window and restrict access to sender IDs and text in Message Viewer.

## References

[Meta Webhooks](https://developers.facebook.com/docs/graph-api/webhooks/getting-started/) · [WhatsApp Business Platform](https://developers.facebook.com/documentation/business-messaging/whatsapp/overview) · [InterSystems %CSP.REST](https://docs.intersystems.com/irislatest/csp/documatic/%25CSP.Documatic.cls?CLASSNAME=%25CSP.REST) · [Community Bounty idea](https://ideas.intersystems.com/ideas/DPI-I-882)

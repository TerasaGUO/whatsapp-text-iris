/// Handle Meta's subscription and signed notifications directly in the production namespace.
Class WaText.Webhook Extends %CSP.REST
{
Parameter CHARSET = "utf-8";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/webhook" Method="GET" Call="Challenge"/>
  <Route Url="/webhook" Method="POST" Call="Notify"/>
</Routes>
}

/// Return the exact challenge text after authenticating the subscription token.
ClassMethod Challenge() As %Status
{
    set token=$system.Util.GetEnviron("WA_VERIFY_TOKEN")
    if token="" { quit ..Reply("503 Service Unavailable") }
    set supplied=%request.Get("hub.verify_token"),challenge=%request.Get("hub.challenge")
    if (%request.Get("hub.mode")'="subscribe") || (challenge="") || ('..Equal($system.Encryption.SHAHash(256,token),$system.Encryption.SHAHash(256,supplied))) {
        quit ..Reply("403 Forbidden")
    }
    quit ..Reply("200 OK",challenge)
}

/// Verify the exact request bytes before UTF-8 decoding, payload parsing, or queue access.
ClassMethod Notify() As %Status
{
    set secret=$system.Util.GetEnviron("WA_APP_SECRET"),phone=$system.Util.GetEnviron("WA_PHONE_ID")
    if (secret="") || (phone'?1.30N) { quit ..Reply("503 Service Unavailable") }
    set stream=%request.Content
    if '$isobject(stream) { quit ..Reply("400 Bad Request") }
    if stream.Size>3145728 { quit ..Reply("413 Payload Too Large") }
    if stream.Size=0 { quit ..Reply("400 Bad Request") }
    set raw=""
    while 'stream.AtEnd { set raw=raw_stream.Read(32768) }
    set digest=$system.Encryption.HMACSHA(256,raw,secret),signature="sha256="
    for i=1:1:$length(digest) {
        set signature=signature_$zconvert($extract($zhex(256+$ascii(digest,i)),2,3),"L")
    }
    if '..Equal(signature,%request.GetCgiEnv("HTTP_X_HUB_SIGNATURE_256")) { quit ..Reply("403 Forbidden") }
    try {
        set json=$zconvert(raw,"I","UTF8")
        set valid=0
        if $zconvert(json,"O","UTF8")=raw {
            set event=##class(%DynamicObject).%FromJSON(json)
            set valid=..Collect(event,phone,.messages)
        }
    } catch bad {
        set valid=0
    }
    if 'valid { quit ..Reply("400 Bad Request") }
    set accepted=1
    try {
        for i=0:1:messages.%Size()-1 {
            set msg=messages.%Get(i)
            if '##class(WaText.Service).Accept(msg.id,msg.from,msg.text.body) { set accepted=0 quit }
        }
    } catch unavailable {
        set accepted=0
    }
    if 'accepted { quit ..Reply("503 Service Unavailable") }
    quit ..Reply("200 OK","ok")
}

/// Validate every text in a batch before enqueueing any and ignore unrelated products or numbers.
ClassMethod Collect(event As %DynamicObject, phone As %String, Output messages As %DynamicArray) As %Boolean
{
    set messages=[]
    if 'event.%IsA("%DynamicObject") { quit 0 }
    if event.object'="whatsapp_business_account" { quit 1 }
    if event.%GetTypeOf("entry")'="array" { quit 0 }
    set entries=event.entry,valid=1
    for i=0:1:entries.%Size()-1 {
        set entry=entries.%Get(i)
        if entry.%GetTypeOf("changes")'="array" { set valid=0 quit }
        set changes=entry.changes
        for j=0:1:changes.%Size()-1 {
            set change=changes.%Get(j)
            if change.field'="messages" { continue }
            set valid=..ReadChange(change.value,phone,messages)
            if 'valid { quit }
        }
        if 'valid { quit }
    }
    quit valid
}

/// Select supported texts from one messages notification for this business number.
ClassMethod ReadChange(value As %DynamicObject, phone As %String, messages As %DynamicArray) As %Boolean [ Private ]
{
    if value.metadata.%GetTypeOf("phone_number_id")'="string" { quit 0 }
    if value.metadata."phone_number_id"'=phone { quit 1 }
    if 'value.%IsDefined("messages") { quit 1 }
    if value.%GetTypeOf("messages")'="array" { quit 0 }
    set batch=value.messages,valid=1
    for k=0:1:batch.%Size()-1 {
        set msg=batch.%Get(k)
        if msg.type'="text" { continue }
        if (msg.%GetTypeOf("id")'="string") || (msg.id="") || ($length(msg.id)>240) { set valid=0 quit }
        if (msg.%GetTypeOf("from")'="string") || (msg.from'?1.20N) { set valid=0 quit }
        if (msg.text.%GetTypeOf("body")'="string") || ($length(msg.text.body)>4096) { set valid=0 quit }
        do messages.%Push(msg)
    }
    quit valid
}

/// Compare fixed-length digests without exiting early on the first differing byte.
ClassMethod Equal(a As %String, b As %String) As %Boolean [ Private ]
{
    if $length(a)'=$length(b) { quit 0 }
    set mismatch=0
    for i=1:1:$length(a) { set mismatch=mismatch+($ascii(a,i)'=$ascii(b,i)) }
    quit mismatch=0
}

/// Write the required HTTP status and optional plain-text response.
ClassMethod Reply(status As %String, body As %String = "") As %Status [ Private ]
{
    set %response.Status=status,%response.ContentType="text/plain"
    write body
    quit $$$OK
}
}

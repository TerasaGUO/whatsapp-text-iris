Class WaText.GraphAdapter Extends Ens.OutboundAdapter
{

Property TLSConfig As %String;
Property GraphVersion As %String;
Property PhoneId As %String;
Parameter SETTINGS = "GraphVersion,PhoneId,TLSConfig";

/// Build a Graph text message and return the message ID from a successful response.
Method SendText(recipient As %String, text As %String, Output remoteId As %String) As %Status
{
    set remoteId=""
    if (..PhoneId'?1.30N) || (..GraphVersion'?1"v"1.3N1"."1.2N) {
        quit $$$ERROR($$$GeneralError,"Set the phone number ID and Graph API version")
    }
    set payload={}
    set payload."messaging_product"="whatsapp",payload.to=recipient,payload.type="text"
    set content={},content.body=text,payload.text=content
    set request=##class(%Net.HttpRequest).%New()
    set sc=..Configure(request)
    if $$$ISERR(sc) { quit sc }
    set request.Timeout=15,request.ContentType="application/json",request.ContentCharset="utf-8"
    do request.EntityBody.Write(payload.%ToJSON())
    set sc=request.Post("/"_..GraphVersion_"/"_..PhoneId_"/messages")
    if $$$ISERR(sc) { quit sc }
    if request.HttpResponse.StatusCode'=200 {
        quit $$$ERROR($$$GeneralError,"Graph returned HTTP "_request.HttpResponse.StatusCode)
    }
    set response=##class(%DynamicObject).%FromJSON(request.HttpResponse.Data)
    set first=response.messages.%Get(0),remoteId=first.id
    if remoteId="" { quit $$$ERROR($$$GeneralError,"Graph response has no message ID") }
    quit $$$OK
}

/// Send the access token only to the Graph API over TLS with hostname verification.
Method Configure(request As %Net.HttpRequest) As %Status
{
    set token=$system.Util.GetEnviron("WA_ACCESS_TOKEN")
    if (token="") || (..TLSConfig="") {
        quit $$$ERROR($$$GeneralError,"Configure WA_ACCESS_TOKEN and TLSConfig")
    }
    set request.Server="graph.facebook.com",request.Https=1,request.Port=443
    set request.SSLConfiguration=..TLSConfig,request.SSLCheckServerIdentity=1
    do request.SetHeader("Authorization","Bearer "_token)
    quit $$$OK
}
}

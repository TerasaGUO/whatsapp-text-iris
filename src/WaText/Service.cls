Class WaText.Service Extends Ens.BusinessService
{

Parameter ADAPTER = "";

/// Pass text authenticated by the gateway to the adapterless service in the running production.
ClassMethod Accept(id As %String, sender As %String, body As %String) As %Boolean
{
    if (id="") || ($length(id)>240) || (sender'?1.20N) || ($length(body)>4096) { quit 0 }
    set sc=##class(Ens.Director).CreateBusinessService("WhatsApp Input",.service)
    if $$$ISERR(sc) { quit 0 }
    set msg=##class(WaText.Message).%New()
    set msg.MetaId=id,msg.Sender=sender,msg.Body=body
    set sc=service.ProcessInput(msg,.output)
    quit $$$ISOK(sc)
}

/// Queue the inbound text for the operation so the webhook can return before Graph replies.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    quit ..SendRequestAsync("WhatsApp Reply",pInput)
}
}

Class WaText.Operation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";
Parameter ADAPTER = "WaText.GraphAdapter";
Property Adapter As WaText.GraphAdapter;
Property ReplyText As %String(MAXLEN = 1000) [ InitialExpression = "Thanks, your text reached IRIS." ];
Parameter SETTINGS = "ReplyText";

/// Lock each inbound message ID and record the attempt before sending, so an uncertain delivery can be reconciled.
Method Reply(msg As WaText.Message, Output response As Ens.Response) As %Status
{
    set id=msg.MetaId,sc=$$$OK
    lock +^WaTextReceipt(id):10
    if '$test { quit $$$ERROR($$$GeneralError,"Could not lock the incoming message ID") }
    try {
        set state=$get(^WaTextReceipt(id))
        if state="" {
            set ^WaTextReceipt(id)="pending"
            set sc=..Adapter.SendText(msg.Sender,..ReplyText,.remoteId)
            if $$$ISOK(sc) { set ^WaTextReceipt(id)=$listbuild("sent",remoteId) }
        } elseif state="pending" {
            set sc=$$$ERROR($$$GeneralError,"Previous delivery requires reconciliation")
        }
    } catch ex {
        set sc=ex.AsStatus()
    }
    lock -^WaTextReceipt(id)
    quit sc
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="WaText.Message"><Method>Reply</Method></MapItem>
</MapItems>
}
}

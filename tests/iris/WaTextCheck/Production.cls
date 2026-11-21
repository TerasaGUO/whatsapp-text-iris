Class WaTextCheck.Production Extends Ens.Production
{
/// Check a test message's receipt without granting the test account direct global access.
ClassMethod Sent(id As %String) As %Boolean
{
    set receipt=$get(^WaTextReceipt(id))
    if '$listvalid(receipt) { quit 0 }
    quit $listget(receipt,1)="sent"
}

/// Confirm that the original Unicode text is stored in the actual production message.
ClassMethod Received(id As %String, body As %String) As %Boolean
{
    &sql(SELECT COUNT(*) INTO :count FROM WaText.Message WHERE MetaId = :id AND Body = :body)
    quit (SQLCODE=0) && (count>0)
}

XData ProductionDefinition
{
<Production Name="WaTextCheck.Production">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="WhatsApp Input" ClassName="WaText.Service" PoolSize="0" Enabled="true"/>
  <Item Name="WhatsApp Reply" ClassName="WaTextCheck.Operation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="PhoneId">7123</Setting>
    <Setting Target="Adapter" Name="GraphVersion">v23.0</Setting>
  </Item>
</Production>
}
}

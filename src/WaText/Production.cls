Class WaText.Production Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="WaText.Production" TestingEnabled="false">
  <Description>Accept signed WhatsApp texts and acknowledge each message.</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="WhatsApp Input" ClassName="WaText.Service" PoolSize="0" Enabled="true"/>
  <Item Name="WhatsApp Reply" ClassName="WaText.Operation" PoolSize="1" Enabled="true"/>
</Production>
}
}

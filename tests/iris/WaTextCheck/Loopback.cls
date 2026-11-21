Class WaTextCheck.Loopback Extends WaText.GraphAdapter
{
/// Connect to the container's loopback test server without reading production credentials.
Method Configure(request As %Net.HttpRequest) As %Status
{
    set request.Server="127.0.0.1",request.Port=18652,request.Https=0
    quit $$$OK
}
}

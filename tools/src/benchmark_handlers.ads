with Web.Request;
with Web.Response;
with Web.Connection;

package Benchmark_Handlers is
   --  Return a small benchmark route response.
   --  @param Request HTTP request.
   --  @return HTTP response.
   function Bench_Handler
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Echo a minimal patch message for benchmark WebSocket text frames.
   --  @param Conn WebSocket connection.
   --  @param Request Upgrade request.
   --  @return No return value.
   procedure Bench_WebSocket
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type);
end Benchmark_Handlers;

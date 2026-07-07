with Web.WebSocket;

package body Benchmark_Handlers is
   function Bench_Handler
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
   begin
      return Web.Response.Text ("ok");
   end Bench_Handler;

   procedure Bench_WebSocket
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type)
   is
      pragma Unreferenced (Request);
      Message : constant String := "{""type"":""patches"",""patches"":[]}";
   begin
      loop
         declare
            Frame : constant Web.WebSocket.Frame := Web.WebSocket.Receive_Frame (Conn, 512);
         begin
            case Frame.Frame_Type is
               when Web.WebSocket.Text_Frame =>
                  Web.WebSocket.Send_Text (Conn, Message);
               when Web.WebSocket.Ping_Frame =>
                  Web.WebSocket.Send_Pong (Conn, Web.WebSocket.Payload (Frame));
               when Web.WebSocket.Pong_Frame =>
                  null;
               when Web.WebSocket.Close_Frame =>
                  Web.WebSocket.Send_Close (Conn);
                  return;
            end case;
         end;
      end loop;
   exception
      when others =>
         null;
   end Bench_WebSocket;
end Benchmark_Handlers;

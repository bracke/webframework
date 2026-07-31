with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Server;
with Web.Response;
with Tracing.Propagation;
package body Webframework_Tracing is

   --  The collector the /traces endpoint dumps; null selects an empty body.
   Target : access Tracing_Runtime.Tracer.Collector := null;

   function Extract_Context
     (Request : Web.Request.Request_Type) return Tracing.Context.Span_Context
   is
      Header : constant String :=
        Web.Request.Header (Request, Traceparent_Header_Name);
      Result : Tracing.Context.Span_Context;
      Ok     : Boolean;
   begin
      Tracing.Propagation.Parse_Traceparent (Header, Result, Ok);
      if Ok then
         return Result;
      end if;
      return Tracing.Context.No_Context;
   end Extract_Context;

   function Traceparent_Header
     (Context : Tracing.Context.Span_Context) return String is
     (Tracing.Propagation.Format_Traceparent (Context));

   procedure Use_Collector
     (Sink : not null access Tracing_Runtime.Tracer.Collector) is
   begin
      Target := Sink;
   end Use_Collector;

   function Dump_Handler
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
      Body_Text : Unbounded_String;
   begin
      if Target /= null then
         for I in 1 .. Target.Count loop
            Append (Body_Text, Target.Line (I));
            Append (Body_Text, Character'Val (10));
         end loop;
      end if;
      return Web.Response.Create (200, To_String (Body_Text), Content_Type);
   end Dump_Handler;

   procedure Install_Dump (Path : String := "/traces") is
   begin
      Web.Server.Get (Path, Dump_Handler'Access);
   end Install_Dump;

end Webframework_Tracing;

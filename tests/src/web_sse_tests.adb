with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;
with Web.SSE;

package body Web_SSE_Tests is

   LF : constant Character := Character'Val (10);

   function Contains (Haystack, Needle : String) return Boolean is
   begin
      if Needle'Length = 0 or else Haystack'Length < Needle'Length then
         return Needle'Length = 0;
      end if;
      for I in Haystack'First .. Haystack'Last - Needle'Length + 1 loop
         if Haystack (I .. I + Needle'Length - 1) = Needle then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   --  Whether every non-empty line of Text begins with Prefix.
   function All_Lines_Start (Text, Prefix : String) return Boolean is
      Start : Integer := Text'First;
   begin
      for I in Text'Range loop
         if Text (I) = LF then
            declare
               Line : constant String := Text (Start .. I - 1);
            begin
               if Line'Length > 0
                 and then (Line'Length < Prefix'Length
                           or else Line (Line'First .. Line'First + Prefix'Length - 1)
                                   /= Prefix)
               then
                  return False;
               end if;
            end;
            Start := I + 1;
         end if;
      end loop;
      return True;
   end All_Lines_Start;

   procedure Test_Simple (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Assert (Web.SSE.Format_Event ("hello") = "data: hello" & LF & LF,
              "simple event framing");
   end Test_Simple;

   procedure Test_Event_And_Id (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Assert (Web.SSE.Format_Event ("x", Event => "tick", Id => "7")
                = "event: tick" & LF & "id: 7" & LF & "data: x" & LF & LF,
              "event + id + data ordering");
   end Test_Event_And_Id;

   procedure Test_Multiline_Data (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      --  Each source line becomes its own data: line; no spurious empty tail.
      Assert (Web.SSE.Format_Event ("a" & LF & "b")
                = "data: a" & LF & "data: b" & LF & LF,
              "multi-line data splits into data: lines");
   end Test_Multiline_Data;

   procedure Test_Empty_Data (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Assert (Web.SSE.Format_Event ("") = "data: " & LF & LF,
              "empty data still emits one data: line");
   end Test_Empty_Data;

   procedure Test_Data_Injection (T : in out Fixture) is
      pragma Unreferenced (T);
      --  A payload that tries to inject its own event/blank line.
      Out_Text : constant String :=
        Web.SSE.Format_Event ("a" & LF & LF & "event: evil" & LF & "data: x");
   begin
      --  Every non-blank line is a data: line: nothing forges a new field.
      Assert (All_Lines_Start (Out_Text, "data: "),
              "injected payload stays inside data: lines");
      Assert (Contains (Out_Text, "data: event: evil"),
              "injected text is escaped as data, not a field");
   end Test_Data_Injection;

   procedure Test_Field_Injection (T : in out Fixture) is
      pragma Unreferenced (T);
      --  CR/LF in the event name must not create extra lines.
      Out_Text : constant String :=
        Web.SSE.Format_Event ("x", Event => "tick" & LF & "data: evil");
   begin
      Assert (Contains (Out_Text, "event: tickdata: evil"),
              "newline stripped from event name");
      Assert (not Contains (Out_Text, "event: tick" & LF & "data: evil"),
              "event name cannot forge a data line");
   end Test_Field_Injection;

   procedure Test_Comment_And_Retry (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Assert (Web.SSE.Format_Comment ("ping") = ": ping" & LF & LF, "comment");
      Assert (Web.SSE.Format_Retry (3000) = "retry: 3000" & LF & LF, "retry");
   end Test_Comment_And_Retry;

   procedure Test_Response_Headers (T : in out Fixture) is
      pragma Unreferenced (T);
      H : constant String := Web.SSE.Response_Headers;
   begin
      Assert (Contains (H, "200 OK"), "status line");
      Assert (Contains (H, "text/event-stream"), "content type");
      Assert (Contains (H, "Cache-Control: no-cache"), "no-cache");
   end Test_Response_Headers;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test (Caller.Create ("SSE: simple", Test_Simple'Access));
      Suite.Add_Test (Caller.Create ("SSE: event+id", Test_Event_And_Id'Access));
      Suite.Add_Test (Caller.Create ("SSE: multi-line data", Test_Multiline_Data'Access));
      Suite.Add_Test (Caller.Create ("SSE: empty data", Test_Empty_Data'Access));
      Suite.Add_Test (Caller.Create ("SSE: data injection", Test_Data_Injection'Access));
      Suite.Add_Test (Caller.Create ("SSE: field injection", Test_Field_Injection'Access));
      Suite.Add_Test (Caller.Create ("SSE: comment+retry", Test_Comment_And_Retry'Access));
      Suite.Add_Test (Caller.Create ("SSE: response headers", Test_Response_Headers'Access));
   end Add_Tests;

end Web_SSE_Tests;

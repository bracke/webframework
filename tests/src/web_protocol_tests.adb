with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;
with Web.Dispatcher;
with Web.Errors;
with Web.Events;
with Web.Html;
with Web.Patch;
with Web.Protocol;

package body Web_Protocol_Tests is
   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Ada.Strings.Unbounded;
   use type Web.Events.Event_Kind;
   use type Web.Patch.Patch_Kind;

   type Test_State is record
      Count : Natural := 0;
   end record;

   function Increment
     (State : in out Test_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;

   package Test_Dispatch is new Web.Dispatcher (Test_State);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("patch constructors", Test_Patches'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("protocol decode", Test_Decode'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("protocol json robustness", Test_JSON_Robustness'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("malformed protocol rejection", Test_Malformed_Rejection'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("patch encode", Test_Encode'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("event helper functions", Test_Event_Helpers'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("dispatcher", Test_Dispatcher'Access));
   end Add_Tests;

   function Increment
     (State : in out Test_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      pragma Unreferenced (Event);
   begin
      State.Count := State.Count + 1;
      return Web.Patch.Single (Web.Patch.Set_Text ("counter-value", "1"));
   end Increment;

   procedure Test_Patches (Item : in out Fixture) is
      pragma Unreferenced (Item);
      List : Web.Patch.Patch_List := Web.Patch.Single (Web.Patch.Set_Text ("counter-value", "1"));
      Raised : Boolean := False;
   begin
      Web.Patch.Append (List, Web.Patch.Add_Class ("counter-value", "active"));
      Web.Patch.Append (List, Web.Patch.Set_Attribute ("counter-value", "data-count", "1"));
      Web.Patch.Append (List, Web.Patch.Remove_Attribute ("counter-value", "aria-hidden"));
      Assert (Natural (List.Items.Length) = 4, "append");
      Assert (Web.Patch.Kind (List.Items (0)) = Web.Patch.Set_Text_Kind, "kind");
      Assert (Web.Patch.Target (List.Items (0)) = "counter-value", "target");
      Assert (Web.Patch.Value (List.Items (0)) = "1", "value");
      Assert (Web.Patch.Name (List.Items (2)) = "data-count", "attribute name stored");
      Assert
        (Web.Patch.Kind
           (Web.Patch.Replace_HTML ("counter-value", Web.Html.Trusted ("<strong>1</strong>"))) =
         Web.Patch.Replace_HTML_Kind,
         "replace html");

      begin
         declare
            Ignored : constant Web.Patch.Patch := Web.Patch.Set_Attribute ("counter-value", "", "x");
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "empty attribute name rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Patch.Patch :=
              Web.Patch.Set_Attribute ("counter-value", "onload=alert", "x");
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "attribute delimiter rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Patch.Patch :=
              Web.Patch.Remove_Attribute ("counter-value", "data" & Character'Val (9) & "x");
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "attribute control byte rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Patch.Patch_List :=
              Web.Patch.Single
                (Web.Patch.Patch'
                   (Patch_Type => Web.Patch.Set_Text_Kind,
                    Target_Id  => To_Unbounded_String ("bad id"),
                    Name_Value => To_Unbounded_String (""),
                    Data_Value => To_Unbounded_String ("x"),
                    Force_Flag => False));
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "raw invalid patch rejected by single");

      Raised := False;
      begin
         Web.Patch.Append
           (List,
            Web.Patch.Patch'
              (Patch_Type => Web.Patch.Add_Class_Kind,
               Target_Id  => To_Unbounded_String ("counter-value"),
               Name_Value => To_Unbounded_String (".bad"),
               Data_Value => To_Unbounded_String (""),
               Force_Flag => False));
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "raw invalid patch rejected by append");
   end Test_Patches;

   procedure Test_Decode (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Hello : constant Web.Events.Event :=
        Web.Protocol.Decode_Client_Message ("{""type"":""hello"",""version"":1}");
      Click : constant Web.Events.Event :=
        Web.Protocol.Decode_Client_Message
          ("{""type"":""click"",""version"":1,""id"":""counter-inc"",""action"":""counter.increment""}");
      Submit : constant Web.Events.Event :=
        Web.Protocol.Decode_Client_Message
          ("{""type"":""submit"",""version"":1,""id"":""profile-form"",""action"":""profile.save"","
           & """fields"":{""name"":""Bent""}}");
      Raised : Boolean := False;
   begin
      Assert (Web.Events.Kind (Hello) = Web.Events.Hello_Event, "hello");
      Assert (Web.Events.Kind (Click) = Web.Events.Click_Event, "click");
      Assert (Web.Events.Action (Click) = "counter.increment", "click action");
      Assert (Web.Events.Kind (Submit) = Web.Events.Submit_Event, "submit");
      Assert (Web.Events.Has_Field (Submit, "name"), "submit field exists");
      Assert (Web.Events.Field (Submit, "name") = "Bent", "submit field value");

      begin
         declare
            Ignored : constant Boolean := Web.Events.Has_Field (Submit, "bad name");
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid Has_Field lookup name rejected");

      Raised := False;
      begin
         declare
            Ignored : constant String := Web.Events.Field (Submit, "bad;name");
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid Field lookup name rejected");
   end Test_Decode;

   procedure Test_JSON_Robustness (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Event : constant Web.Events.Event :=
        Web.Protocol.Decode_Client_Message
          ("{"
           & """ignored"":{""nested"":[true,false,null,{""x"":1}]},"
           & """fields"":{""name"":""Bent \""Ada\"" Bracke"",""note"":""line\nnext"",""city"":""K\u00F8benhavn""},"
           & """action"":""profile.save"","
           & """id"":""profile-form"","
           & """version"":1,"
           & """type"":""submit"""
           & "}");
   begin
      Assert (Web.Events.Kind (Event) = Web.Events.Submit_Event, "submit kind");
      Assert (Web.Events.Field (Event, "name") = "Bent ""Ada"" Bracke", "quote escape decoded");
      Assert
        (Web.Events.Field (Event, "note") = "line" & Character'Val (10) & "next",
         "newline escape decoded");
      Assert
        (Web.Events.Field (Event, "city") = "K" & Character'Val (16#C3#) & Character'Val (16#B8#)
         & "benhavn",
         "unicode escape decoded as utf-8");
   end Test_JSON_Robustness;

   procedure Test_Malformed_Rejection (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Raised : Boolean := False;

      procedure Expect_Protocol_Error (Message : String; Name : String) is
         Local_Raised : Boolean := False;
      begin
         begin
            declare
               Event : constant Web.Events.Event := Web.Protocol.Decode_Client_Message (Message);
            begin
               Assert (Web.Events.Action (Event)'Length = 0, Name & " unexpectedly decoded");
            end;
         exception
            when Web.Errors.Protocol_Error =>
               Local_Raised := True;
         end;
         Assert (Local_Raised, Name);
      end Expect_Protocol_Error;

      function Many_Fields_Message return String is
         Fields : Unbounded_String := To_Unbounded_String ("{");
      begin
         for Index_Value in 1 .. Web.Events.Max_Field_Count + 1 loop
            if Index_Value > 1 then
               Append (Fields, ",");
            end if;

            Append
              (Fields,
               """f"
               & Ada.Strings.Fixed.Trim (Natural'Image (Index_Value), Ada.Strings.Both)
               & """:""x""");
         end loop;

         Append (Fields, "}");
         return
           "{""type"":""submit"",""version"":1,""id"":""profile-form"","
           & """action"":""profile.save"",""fields"":"
           & To_String (Fields)
           & "}";
      end Many_Fields_Message;

      function Oversized_Ignored_String_Message return String is
         Value : Unbounded_String;
      begin
         for Index_Value in 1 .. Web.Events.Max_Field_Value_Length + 1 loop
            Append (Value, "x");
         end loop;

         return
           "{""ignored"":"""
           & To_String (Value)
           & """,""type"":""hello"",""version"":1}";
      end Oversized_Ignored_String_Message;
   begin
      begin
         declare
            Event : constant Web.Events.Event :=
              Web.Protocol.Decode_Client_Message ("{""type"":""click"",""version"":1}");
         begin
            Assert (Web.Events.Action (Event)'Length = 0, "unreachable");
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "missing fields rejected");

      Expect_Protocol_Error ("{""type"":""hello"",""version"":2}", "unsupported version rejected");
      Expect_Protocol_Error ("{""type"":""hello"",""version"":01}", "leading-zero version rejected");
      Expect_Protocol_Error ("{""type"":""hello"",""version"":1} true", "trailing data rejected");
      Expect_Protocol_Error ("{""type"":""hello"",""version"":1", "unterminated object rejected");
      Expect_Protocol_Error
        ("{""type"":""submit"",""version"":1,""id"":""x"",""action"":""a"",""fields"":[]}",
         "fields array rejected");
      Expect_Protocol_Error
        ("{""type"":""submit"",""version"":1,""id"":""x"",""action"":""a"",""fields"":{""x"":1}}",
         "non-string field rejected");
      Expect_Protocol_Error
        ("{""type"":""click"",""version"":1,""id"":""x"",""action"":""bad\q""}",
         "bad escape rejected");
      Expect_Protocol_Error
        ("{""type"":""submit"",""version"":1,""id"":""profile-form"","
         & """action"":""profile.save"",""fields"":{""name"":""bad\uD800value""}}",
         "unicode surrogate rejected");
      Expect_Protocol_Error
        ("{""type"":""click"",""version"":1,""id"":""bad id"",""action"":""counter.increment""}",
         "invalid element id rejected");
      Expect_Protocol_Error
        ("{""type"":""click"",""version"":1,""id"":""counter-inc"",""action"":""bad action""}",
         "invalid action rejected");
      Expect_Protocol_Error
        ("{""type"":""click"",""type"":""submit"",""version"":1,"
         & """id"":""counter-inc"",""action"":""counter.increment""}",
         "duplicate type rejected");
      Expect_Protocol_Error
        ("{""type"":""submit"",""version"":1,""id"":""profile-form"","
         & """action"":""profile.save"",""fields"":{""name"":""one"",""name"":""two""}}",
         "duplicate field rejected");
      Expect_Protocol_Error (Many_Fields_Message, "too many fields rejected");
      Expect_Protocol_Error
        (Oversized_Ignored_String_Message,
         "oversized ignored string rejected");
   end Test_Malformed_Rejection;

   procedure Test_Encode (Item : in out Fixture) is
      pragma Unreferenced (Item);
      List : constant Web.Patch.Patch_List :=
        Web.Patch.Single (Web.Patch.Set_Text ("counter-value", "1"));
      Json : constant String := Web.Protocol.Encode_Patches (List);
      Control_List : constant Web.Patch.Patch_List :=
        Web.Patch.Single
          (Web.Patch.Set_Text
             ("counter-value",
              Character'Val (1) & Character'Val (127) & Character'Val (128) & "x"));
      Control_Json : constant String := Web.Protocol.Encode_Patches (Control_List);
      Invalid_Target_List : Web.Patch.Patch_List;
      Invalid_Name_List : Web.Patch.Patch_List;
      Raised : Boolean := False;
   begin
      Assert
        (Json =
         "{""type"":""patches"",""patches"":[{""op"":""set_text"",""target"":""counter-value"","
         & """value"":""1""}]}",
         "encoded patches");
      Assert
        (Ada.Strings.Fixed.Index (Control_Json, "\u0001\u007F\u0080x") > 0,
         "control bytes escaped in patch json");

      Invalid_Target_List.Items.Append
        (Web.Patch.Patch'
           (Patch_Type => Web.Patch.Set_Text_Kind,
            Target_Id  => To_Unbounded_String ("bad id"),
            Name_Value => To_Unbounded_String (""),
            Data_Value => To_Unbounded_String ("x"),
            Force_Flag => False));

      begin
         declare
            Ignored : constant String := Web.Protocol.Encode_Patches (Invalid_Target_List);
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "raw patch invalid target rejected during encode");

      Invalid_Name_List.Items.Append
        (Web.Patch.Patch'
           (Patch_Type => Web.Patch.Set_Attribute_Kind,
            Target_Id  => To_Unbounded_String ("counter-value"),
            Name_Value => To_Unbounded_String ("onload=alert"),
            Data_Value => To_Unbounded_String ("x"),
            Force_Flag => False));

      Raised := False;
      begin
         declare
            Ignored : constant String := Web.Protocol.Encode_Patches (Invalid_Name_List);
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "raw patch invalid attribute rejected during encode");
   end Test_Encode;

   procedure Test_Event_Helpers (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Event       : Web.Events.Event := Web.Events.Create (Web.Events.Submit_Event, "demo", "demo.save");
      Missing_Text : constant String := "missing text";
      Raised      : Boolean := False;
   begin
      Web.Events.Set_Field (Event, "name", "  alice  ");
      Web.Events.Set_Field (Event, "count", "42");
      Web.Events.Set_Field (Event, "enabled", "1");
      Web.Events.Set_Field (Event, "broken", "abc");

      Assert (Web.Events.Field (Event, "name") = "  alice  ", "raw field value");
      Assert
        (Web.Events.Field_Or_Default (Event, "missing", Missing_Text) = Missing_Text,
         "field default value");
      Assert
        (Web.Events.Required_Non_Empty_Field (Event, "name") = "alice",
         "required field trimmed");
      Assert
        (Web.Events.Integer_Field (Event, "count", 3) = 42, "integer parse");
      Assert
        (Web.Events.Integer_Field (Event, "missing", 3) = 3, "integer fallback");
      Assert
        (Web.Events.Boolean_Field (Event, "enabled", False) = True, "boolean parse");
      Assert
        (Web.Events.Boolean_Field (Event, "missing", False) = False, "boolean fallback");
      Assert
        (Web.Events.Boolean_Field (Event, "broken", True) = True, "boolean invalid fallback");

      begin
         declare
            Ignored : constant String := Web.Events.Required_Field (Event, "none");
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "required field raises");

      Raised := False;
      begin
         declare
            Ignored : constant String := Web.Events.Field (Event, "bad name");
         begin
            null;
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid field lookup rejected");
   end Test_Event_Helpers;

   procedure Test_Dispatcher (Item : in out Fixture) is
      pragma Unreferenced (Item);
      State : Test_State;
      Event : constant Web.Events.Event :=
        Web.Events.Create (Web.Events.Click_Event, "counter-inc", "test.increment");
      Patches : Web.Patch.Patch_List;
      Raised : Boolean;
   begin
      Test_Dispatch.Register ("test.increment", Increment'Access);

      Raised := False;
      begin
         Test_Dispatch.Register ("test.increment", Increment'Access);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "duplicate action rejected");

      Raised := False;
      begin
         Test_Dispatch.Register ("", Increment'Access);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "empty action rejected");

      Raised := False;
      begin
         Test_Dispatch.Register ("bad action", Increment'Access);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "malformed action rejected");

      Raised := False;
      begin
         Test_Dispatch.Register ((1 .. Web.Events.Max_Action_Length + 1 => 'a'), Increment'Access);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "overlong action rejected");

      Raised := False;
      begin
         Test_Dispatch.Register ("test.null", null);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "null action handler rejected");

      Raised := False;
      begin
         declare
            Bad_Event : constant Web.Events.Event :=
              Web.Events.Create (Web.Events.Click_Event, "bad id", "test.increment");
         begin
            Assert (Web.Events.Action (Bad_Event)'Length = 0, "unreachable invalid event");
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, "direct invalid event rejected");

      Patches := Test_Dispatch.Dispatch (State, Event);
      Assert (State.Count = 1, "state mutated");
      Assert (Natural (Patches.Items.Length) = 1, "patch returned");
      Patches := Test_Dispatch.Dispatch
        (State, Web.Events.Create (Web.Events.Click_Event, "other", "missing.action"));
      Assert (Natural (Patches.Items.Length) = 0, "unknown action safe");
   end Test_Dispatcher;
end Web_Protocol_Tests;

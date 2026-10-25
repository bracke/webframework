with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Webframework_Logging is
   use Ada.Strings.Unbounded;

   --  Process-global settings, guarded for concurrent access.
   protected Settings is
      procedure Set_Min (L : Level_Type);
      function Min return Level_Type;
      procedure Set_Struct (On : Boolean);
      function Struct return Boolean;
   private
      Cur_Min   : Level_Type := Debug_Level;
      Struct_On : Boolean := False;
   end Settings;

   protected body Settings is
      procedure Set_Min (L : Level_Type) is
      begin
         Cur_Min := L;
      end Set_Min;
      function Min return Level_Type is (Cur_Min);
      procedure Set_Struct (On : Boolean) is
      begin
         Struct_On := On;
      end Set_Struct;
      function Struct return Boolean is (Struct_On);
   end Settings;

   function Level_Name (Level : Level_Type) return String is
     (case Level is
         when Debug_Level => "debug",
         when Info_Level  => "info",
         when Warn_Level  => "warn",
         when Error_Level => "error");

   function Escape (Value : String; JSON : Boolean) return String is
      Result : Unbounded_String;
   begin
      for Ch of Value loop
         case Ch is
            when '"' =>
               Append (Result, [1 => '\', 2 => '"']);
            when '\' =>
               Append (Result, [1 => '\', 2 => '\']);
            when Character'Val (10) =>
               Append (Result, "\n");
            when Character'Val (13) =>
               Append (Result, "\r");
            when Character'Val (9) =>
               Append (Result, "\t");
            when others =>
               if JSON and then Character'Pos (Ch) < 32 then
                  Append (Result, "?");
               else
                  Append (Result, Ch);
               end if;
         end case;
      end loop;
      return To_String (Result);
   end Escape;

   procedure Put (L : Level_Type; Message : String) is
      Is_Structured : Boolean;
   begin
      if L < Settings.Min then
         return;
      end if;
      Is_Structured := Settings.Struct;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         (if Is_Structured then
             "{""level"":""" & Level_Name (L) & """,""message"":"""
             & Escape (Message, JSON => True) & """}"
          else
             "level=" & Level_Name (L) & " message="""
             & Escape (Message, JSON => False) & '"'));
   exception
      when others =>
         --  Diagnostics must never interfere with request processing.
         null;
   end Put;

   procedure Set_Minimum_Level (Level : Level_Type) is
   begin
      Settings.Set_Min (Level);
   end Set_Minimum_Level;

   function Minimum_Level return Level_Type is (Settings.Min);

   function Enabled (Level : Level_Type) return Boolean is
     (Level >= Settings.Min);

   procedure Set_Structured (Enabled : Boolean) is
   begin
      Settings.Set_Struct (Enabled);
   end Set_Structured;

   function Structured return Boolean is (Settings.Struct);

   procedure Debug (Message : String) is
   begin
      Put (Debug_Level, Message);
   end Debug;

   procedure Info (Message : String) is
   begin
      Put (Info_Level, Message);
   end Info;

   procedure Warn (Message : String) is
   begin
      Put (Warn_Level, Message);
   end Warn;

   procedure Error (Message : String) is
   begin
      Put (Error_Level, Message);
   end Error;

end Webframework_Logging;

with Ada.Text_IO;

package body Web.Logging is
   protected Settings is
      procedure Set_Minimum_Level (Level : Level_Type);
      function Minimum_Level return Level_Type;
      procedure Set_Structured (Enabled : Boolean);
      function Structured return Boolean;
   private
      Current_Minimum : Level_Type := Debug_Level;
      Structured_Output : Boolean := False;
   end Settings;

   protected body Settings is
      procedure Set_Minimum_Level (Level : Level_Type) is
      begin
         Current_Minimum := Level;
      end Set_Minimum_Level;

      function Minimum_Level return Level_Type is
      begin
         return Current_Minimum;
      end Minimum_Level;

      procedure Set_Structured (Enabled : Boolean) is
      begin
         Structured_Output := Enabled;
      end Set_Structured;

      function Structured return Boolean is
      begin
         return Structured_Output;
      end Structured;
   end Settings;

   function Level_Name (Level : Level_Type) return String is
   begin
      case Level is
         when Debug_Level =>
            return "debug";
         when Info_Level =>
            return "info";
         when Warn_Level =>
            return "warn";
         when Error_Level =>
            return "error";
      end case;
   end Level_Name;

   function Escaped (Value : String) return String is
      Result : String (1 .. Value'Length);
   begin
      for Offset in Value'Range loop
         if Character'Pos (Value (Offset)) < 32
           or else Character'Pos (Value (Offset)) = 127
         then
            Result (Offset - Value'First + Result'First) := ' ';
         else
            Result (Offset - Value'First + Result'First) := Value (Offset);
         end if;
      end loop;
      return Result;
   end Escaped;

   procedure Put (Level : Level_Type; Message : String; Use_Error : Boolean := False) is
      Name : constant String := Level_Name (Level);
   begin
      if Level < Settings.Minimum_Level then
         return;
      end if;

      if Use_Error then
         if Settings.Structured then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "level=" & Name & " message=""" & Escaped (Message) & """");
         else
            Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "[" & Name & "] " & Message);
         end if;
      elsif Settings.Structured then
         Ada.Text_IO.Put_Line ("level=" & Name & " message=""" & Escaped (Message) & """");
      else
         Ada.Text_IO.Put_Line ("[" & Name & "] " & Message);
      end if;
   end Put;

   procedure Set_Minimum_Level (Level : Level_Type) is
   begin
      Settings.Set_Minimum_Level (Level);
   end Set_Minimum_Level;

   function Minimum_Level return Level_Type is
   begin
      return Settings.Minimum_Level;
   end Minimum_Level;

   function Enabled (Level : Level_Type) return Boolean is
   begin
      return Level >= Settings.Minimum_Level;
   end Enabled;

   procedure Set_Structured (Enabled : Boolean) is
   begin
      Settings.Set_Structured (Enabled);
   end Set_Structured;

   function Structured return Boolean is
   begin
      return Settings.Structured;
   end Structured;

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
      Put (Error_Level, Message, True);
   end Error;
end Web.Logging;

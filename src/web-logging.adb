with Ada.Text_IO;

package body Web.Logging is
   procedure Put (Level : String; Message : String; Use_Error : Boolean := False) is
   begin
      if Use_Error then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "[" & Level & "] " & Message);
      else
         Ada.Text_IO.Put_Line ("[" & Level & "] " & Message);
      end if;
   end Put;

   procedure Debug (Message : String) is
   begin
      Put ("debug", Message);
   end Debug;

   procedure Info (Message : String) is
   begin
      Put ("info", Message);
   end Info;

   procedure Warn (Message : String) is
   begin
      Put ("warn", Message);
   end Warn;

   procedure Error (Message : String) is
   begin
      Put ("error", Message, True);
   end Error;
end Web.Logging;

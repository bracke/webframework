with Ada.Text_IO;
package body App.Tls_Fixture is

   procedure Write_Certificate (Path : String; Ok : out Boolean) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path, Form => "shared=no");
      Ada.Text_IO.Put (File, Certificate_PEM);
      Ada.Text_IO.Close (File);
      Ok := True;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Ok := False;
   end Write_Certificate;

end App.Tls_Fixture;

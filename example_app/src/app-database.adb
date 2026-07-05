with Ada.Directories;

package body App.Database is
   Database_Path : constant Wide_Wide_String := "example_app.db";

   DB_Handle : Standard.Database.Handle;

   protected Gate is
      entry Acquire;
      procedure Release;
   private
      Busy : Boolean := False;
   end Gate;

   protected body Gate is
      entry Acquire when not Busy is
      begin
         Busy := True;
      end Acquire;

      procedure Release is
      begin
         Busy := False;
      end Release;
   end Gate;

   procedure Open_If_Needed is
   begin
      if Standard.Database.Is_Open (DB_Handle) then
         return;
      end if;

      if Ada.Directories.Exists ("example_app.db") then
         Standard.Database.Open (DB_Handle, Database_Path);
      else
         Standard.Database.Create (DB_Handle, Database_Path);
      end if;

      if not Standard.Database.Last_Operation_Succeeded (DB_Handle) then
         raise Program_Error with "database open failed";
      end if;
   end Open_If_Needed;

   procedure Initialize is
   begin
      Gate.Acquire;
      begin
         Open_If_Needed;
         Gate.Release;
      exception
         when others =>
            Gate.Release;
            raise;
      end;
   end Initialize;

   procedure With_Database (Process : not null access procedure (DB : in out Standard.Database.Handle)) is
   begin
      Gate.Acquire;
      begin
         Open_If_Needed;
         Process.all (DB_Handle);
         Gate.Release;
      exception
         when others =>
            Gate.Release;
            raise;
      end;
   end With_Database;

   procedure Close is
   begin
      Gate.Acquire;
      begin
         if Standard.Database.Is_Open (DB_Handle) then
            Standard.Database.Close (DB_Handle);
         end if;
         Gate.Release;
      exception
         when others =>
            Gate.Release;
            raise;
      end;
   end Close;
end App.Database;

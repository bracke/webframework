with Ada.Directories;

package body App.Database is
   --  One carrier file, named once (the narrow form is for Ada.Directories,
   --  the wide form is what the storage engine's API takes).
   Database_File : constant String          := "example_app.db";
   Database_Path : constant Wide_Wide_String := "example_app.db";

   --  Bounded retry for transient cross-process lock contention on open.
   Max_Open_Attempts : constant := 5;
   Open_Backoff      : constant Duration := 0.050;  --  50 ms between attempts

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
         --  Serialize DB access across websocket handlers and startup/shutdown.
         Busy := True;
      end Acquire;

      procedure Release is
      begin
         --  Always clear busy state before other requests can continue.
         Busy := False;
      end Release;
   end Gate;

   procedure Open_If_Needed is
      use type Standard.Database.Status_Code;
   begin
      --  Open lazily once, reuse handle for subsequent requests.
      if Standard.Database.Is_Open (DB_Handle) then
         return;
      end if;

      --  Runs between the gate's Acquire and Release (not inside a protected
      --  body), so the backoff delay below is permitted and only stalls this
      --  process's own already-serialized access.
      for Attempt in 1 .. Max_Open_Attempts loop
         if Ada.Directories.Exists (Database_File) then
            Standard.Database.Open (DB_Handle, Database_Path);
         else
            Standard.Database.Create (DB_Handle, Database_Path);
         end if;

         exit when Standard.Database.Last_Operation_Succeeded (DB_Handle);

         --  Retry only transient cross-process lock contention; a corrupt file
         --  or I/O error is fatal and must not be spun on.
         declare
            Status : constant Standard.Database.Status_Code :=
              Standard.Database.Last_Result (DB_Handle).Code;
         begin
            if Status /= Standard.Database.Lock_Error
              or else Attempt = Max_Open_Attempts
            then
               raise Storage_Unavailable
                 with "database open failed: " & Status'Image;
            end if;
         end;

         delay Open_Backoff;
      end loop;
   end Open_If_Needed;

   procedure Initialize is
   begin
      --  App startup hook: ensure DB handle is created before first request.
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
      --  Execute storage callback under gate lock to avoid races in callbacks.
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
      --  Safe shutdown path: close handle only if open.
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

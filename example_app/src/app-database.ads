with Database;

--  Database lifecycle and serialized access facade for example app persistence.
package App.Database is
   --  Open/create and prepare storage.
   --  Initialize persistence storage.
   --  @return No return value.
   procedure Initialize;

   --  Execute DB work while holding a process-wide gate.
   --  Serialize access to the app database handle.
   --  @param Process Callback executed with the open database handle.
   --  @return No return value.
   procedure With_Database (Process : not null access procedure (DB : in out Standard.Database.Handle));

   --  Close database handle at application shutdown.
   --  Close persistence storage.
   --  @return No return value.
   procedure Close;
end App.Database;

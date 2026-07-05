with Database;

package App.Database is
   --  Initialize persistence storage.
   --  @return No return value.
   procedure Initialize;

   --  Serialize access to the app database handle.
   --  @param Process Callback executed with the open database handle.
   --  @return No return value.
   procedure With_Database (Process : not null access procedure (DB : in out Standard.Database.Handle));

   --  Close persistence storage.
   --  @return No return value.
   procedure Close;
end App.Database;

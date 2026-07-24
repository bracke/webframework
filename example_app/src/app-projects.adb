with Ada.Characters.Conversions;
with Ada.Strings.Wide_Wide_Unbounded;
with App.Database;
with Database.Catalog;
with Database.Predicates;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

package body App.Projects is
   use Ada.Strings.Wide_Wide_Unbounded;

   --  Internal project row type for database operations
   type Project_Row is record
      Id              : Natural := 0;
      Name            : Unbounded_Wide_Wide_String;
      Status          : Unbounded_Wide_Wide_String;
      Project_Type    : Unbounded_Wide_Wide_String;
      Functions       : Unbounded_Wide_Wide_String;
      Has_Project_Tools : Boolean := False;
      Has_GNAT        : Boolean := False;
      Has_GitHub      : Boolean := False;
      Has_Alire       : Boolean := False;
   end record;

   --  Function to convert project row to database row
   function To_Row (Item : Project_Row) return Standard.Database.Rows.Row;

   --  Function to convert database row to project row
   function From_Row (Row : Standard.Database.Rows.Row) return Project_Row;

   --  Function to extract key from project row
   function Key_Of (Item : Project_Row) return Natural;

   --  Function to convert key to database value
   function Key_Value (Key : Natural) return Standard.Database.Values.Value;

   --  Typed table package for projects
   package Project_Tables is new Standard.Database.Tables.Typed
     (Row_Type  => Project_Row,
      Key_Type  => Natural,
      To_Row    => To_Row,
      From_Row  => From_Row,
      Key_Of    => Key_Of,
      Key_Value => Key_Value);

   --  Table schema
   Schema : Standard.Database.Schema.Table_Schema;

   --  Track if schema has been registered
   Registered : Boolean := False;

   --  Helper function to convert to wide wide string
   function To_Wide (Text : String) return Wide_Wide_String is
   begin
      return Ada.Characters.Conversions.To_Wide_Wide_String (Text);
   end To_Wide;

   --  Helper function to convert from wide wide string
   function To_Narrow (Text : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Text);
   end To_Narrow;

   --  Create the projects table schema
   function New_Schema return Standard.Database.Schema.Table_Schema is
      Result : Standard.Database.Schema.Table_Schema;
   begin
      Result.Name := To_Unbounded_Wide_Wide_String ("projects");

      --  Add columns for the project fields
      Standard.Database.Schema.Add_Column
        (Result,
         Name        => "id",
         Kind        => Standard.Database.Types.Integer_Value,
         Nullable    => False,
         Primary_Key => True);

      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "name",
         Kind     => Standard.Database.Types.Text_Value,
         Nullable => False);

      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "status",
         Kind     => Standard.Database.Types.Text_Value,
         Nullable => False);

      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "project_type",
         Kind     => Standard.Database.Types.Text_Value,
         Nullable => False);

      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "functions",
         Kind     => Standard.Database.Types.Text_Value,
         Nullable => False);

      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "has_project_tools",
         Kind     => Standard.Database.Types.Integer_Value, --  Boolean as 0/1
         Nullable => False);

      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "has_gnat",
         Kind     => Standard.Database.Types.Integer_Value, --  Boolean as 0/1
         Nullable => False);

      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "has_github",
         Kind     => Standard.Database.Types.Integer_Value, --  Boolean as 0/1
         Nullable => False);

      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "has_alire",
         Kind     => Standard.Database.Types.Integer_Value, --  Boolean as 0/1
         Nullable => False);

      return Result;
   end New_Schema;

   --  Convert internal project row to database row
   function To_Row (Item : Project_Row) return Standard.Database.Rows.Row is
      Result : Standard.Database.Rows.Row;
   begin
      --  Add all fields to the row
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Integer (Integer (Item.Id)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Text
           (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Item.Name)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Text
           (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Item.Status)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Text
           (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Item.Project_Type)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Text
           (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Item.Functions)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Integer (Boolean'Pos (Item.Has_Project_Tools)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Integer (Boolean'Pos (Item.Has_GNAT)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Integer (Boolean'Pos (Item.Has_GitHub)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Integer (Boolean'Pos (Item.Has_Alire)));
      return Result;
   end To_Row;

   --  Convert database row to internal project row
   function From_Row (Row : Standard.Database.Rows.Row) return Project_Row is
   begin
      return Project_Row'
        (Id              => Natural (Standard.Database.Rows.Get (Row, 0).Int),
         Name            => Standard.Database.Rows.Get (Row, 1).Text,
         Status          => Standard.Database.Rows.Get (Row, 2).Text,
         Project_Type    => Standard.Database.Rows.Get (Row, 3).Text,
         Functions       => Standard.Database.Rows.Get (Row, 4).Text,
         Has_Project_Tools => Standard.Database.Rows.Get (Row, 5).Int /= 0,
         Has_GNAT        => Standard.Database.Rows.Get (Row, 6).Int /= 0,
         Has_GitHub      => Standard.Database.Rows.Get (Row, 7).Int /= 0,
         Has_Alire       => Standard.Database.Rows.Get (Row, 8).Int /= 0);
   end From_Row;

   --  Extract key from project row
   function Key_Of (Item : Project_Row) return Natural is
   begin
      return Item.Id;
   end Key_Of;

   --  Convert key to database value
   function Key_Value (Key : Natural) return Standard.Database.Values.Value is
   begin
      return Standard.Database.Values.From_Integer (Integer (Key));
   end Key_Value;

   --  Helper function to handle database errors
   procedure Raise_On_Error
     (Result  : Standard.Database.Status.Result;
      Message : String) is
   begin
      if not Standard.Database.Status.Is_Ok (Result) then
         raise Constraint_Error with Message;
      end if;
   end Raise_On_Error;

   --  Ensure the projects table is registered
   procedure Ensure_Registered (DB : in out Standard.Database.Handle) is
      Result : Standard.Database.Status.Result;
   begin
      if Registered then
         return;
      end if;

      Schema := New_Schema;
      Result := Project_Tables.Register (DB, Schema);
      if Standard.Database.Status.Is_Ok (Result) then
         Registered := True;
         return;
      end if;

      --  Table might already exist, try to find it
      Result := Standard.Database.Catalog.Find_By_Name ("projects", Schema);
      if Standard.Database.Status.Is_Ok (Result) then
         Registered := True;
         return;
      end if;

      raise Constraint_Error with "projects table registration failed";
   end Ensure_Registered;

   --  Get next available ID
   function Next_Id
     (DB : in out Standard.Database.Handle;
      Tx : in out Standard.Database.Transactions.Transaction) return Natural
   is
      Cursor : Project_Tables.Cursor;
      Result : Standard.Database.Status.Result;
      Next   : Natural := 1;
   begin
      Result := Project_Tables.Scan
        (Tx, DB, Schema, Standard.Database.Predicates.True_Predicate, Cursor);
      Raise_On_Error (Result, "projects id scan failed");

      while Project_Tables.Has_Element (Cursor) loop
         declare
            Item : constant Project_Row := Project_Tables.Element (Cursor);
         begin
            if Item.Id >= Next then
               Next := Item.Id + 1;
            end if;
         end;

         Result := Project_Tables.Next
           (Tx, DB, Schema, Standard.Database.Predicates.True_Predicate, Cursor);
         exit when not Standard.Database.Status.Is_Ok (Result);
      end loop;

      return Next;
   end Next_Id;

   --  Add a project to the database
   procedure Add_Project
     (Name        : String;
      Status      : String;
      Project_Type : String;
      Functions   : String;
      Has_Project_Tools : Boolean;
      Has_GNAT        : Boolean;
      Has_GitHub      : Boolean;
      Has_Alire       : Boolean) is

      procedure Insert_Project (DB : in out Standard.Database.Handle) is
         Tx     : Standard.Database.Transactions.Transaction;
         Result : Standard.Database.Status.Result;
      begin
         Ensure_Registered (DB);
         Standard.Database.Transactions.Begin_Write (DB, Tx);

         Result := Project_Tables.Insert
           (Tx, DB, Schema,
            Project_Row'
              (Id              => Next_Id (DB, Tx),
               Name            => To_Unbounded_Wide_Wide_String (To_Wide (Name)),
               Status          => To_Unbounded_Wide_Wide_String (To_Wide (Status)),
               Project_Type    => To_Unbounded_Wide_Wide_String (To_Wide (Project_Type)),
               Functions       => To_Unbounded_Wide_Wide_String (To_Wide (Functions)),
               Has_Project_Tools => Has_Project_Tools,
               Has_GNAT        => Has_GNAT,
               Has_GitHub      => Has_GitHub,
               Has_Alire       => Has_Alire));

         if Standard.Database.Status.Is_Ok (Result) then
            Result := Standard.Database.Transactions.Commit (Tx);
            Raise_On_Error (Result, "projects commit failed");
         else
            Standard.Database.Transactions.Rollback (Tx);
            Raise_On_Error (Result, "projects insert failed");
         end if;
      end Insert_Project;
   begin
      App.Database.With_Database (Insert_Project'Access);
   end Add_Project;

   --  Initialize the projects table with some sample data
   procedure Initialize is
      procedure Insert_Sample_Projects (DB : in out Standard.Database.Handle) is
         Tx     : Standard.Database.Transactions.Transaction;
         Result : Standard.Database.Status.Result;
      begin
         Ensure_Registered (DB);

         --  Check if there are already projects in the database
         declare
            Cursor : Project_Tables.Cursor;
            Count  : Natural := 0;
         begin
            Standard.Database.Transactions.Begin_Read (DB, Tx);
            Result := Project_Tables.Scan
              (Tx, DB, Schema, Standard.Database.Predicates.True_Predicate, Cursor);

            if Standard.Database.Status.Is_Ok (Result) then
               while Project_Tables.Has_Element (Cursor) loop
                  Count := Count + 1;
                  exit when Count > 0; --  If we have at least one, skip sample data
                  Result := Project_Tables.Next
                    (Tx, DB, Schema, Standard.Database.Predicates.True_Predicate, Cursor);
                  exit when not Standard.Database.Status.Is_Ok (Result);
               end loop;
            end if;

            Result := Standard.Database.Transactions.Commit (Tx);

            --  If no projects exist, add sample data
            if Count = 0 then
               --  Start a write transaction for inserting sample data
               Standard.Database.Transactions.Begin_Write (DB, Tx);

               --  Add sample projects directly within the transaction
               Result := Project_Tables.Insert
                 (Tx, DB, Schema,
                  Project_Row'
                    (Id              => Next_Id (DB, Tx),
                     Name            => To_Unbounded_Wide_Wide_String (To_Wide ("Web Framework")),
                     Status          => To_Unbounded_Wide_Wide_String (To_Wide ("Active")),
                     Project_Type    => To_Unbounded_Wide_Wide_String (To_Wide ("Library")),
                     Functions       => To_Unbounded_Wide_Wide_String (To_Wide ("HTTP, WebSocket, Static Files")),
                     Has_Project_Tools => True,
                     Has_GNAT        => True,
                     Has_GitHub      => True,
                     Has_Alire       => True));
               Raise_On_Error (Result, "sample project 1 insert failed");

               Result := Project_Tables.Insert
                 (Tx, DB, Schema,
                  Project_Row'
                    (Id              => Next_Id (DB, Tx),
                     Name            => To_Unbounded_Wide_Wide_String (To_Wide ("Database Layer")),
                     Status          => To_Unbounded_Wide_Wide_String (To_Wide ("Stable")),
                     Project_Type    => To_Unbounded_Wide_Wide_String (To_Wide ("Library")),
                     Functions       => To_Unbounded_Wide_Wide_String (To_Wide ("SQL, ORM, Transactions")),
                     Has_Project_Tools => False,
                     Has_GNAT        => True,
                     Has_GitHub      => False,
                     Has_Alire       => True));
               Raise_On_Error (Result, "sample project 2 insert failed");

               Result := Project_Tables.Insert
                 (Tx, DB, Schema,
                  Project_Row'
                    (Id              => Next_Id (DB, Tx),
                     Name            => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("CLI Tool")),
                     Status          => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("Development")),
                     Project_Type    => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("Application")),
                     Functions       => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("Command Line Interface, Build") &
                                        " System"),
                     Has_Project_Tools => True,
                     Has_GNAT        => True,
                     Has_GitHub      => True,
                     Has_Alire       => False));
               Raise_On_Error (Result, "sample project 3 insert failed");

               Result := Project_Tables.Insert
                 (Tx, DB, Schema,
                  Project_Row'
                    (Id              => Next_Id (DB, Tx),
                     Name            => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("Web Application")),
                     Status          => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("Testing")),
                     Project_Type    => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("Application")),
                     Functions       => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("User Management, Authentication,") &
                                        " Logging"),
                     Has_Project_Tools => True,
                     Has_GNAT        => True,
                     Has_GitHub      => True,
                     Has_Alire       => True));
               Raise_On_Error (Result, "sample project 4 insert failed");

               Result := Project_Tables.Insert
                 (Tx, DB, Schema,
                  Project_Row'
                    (Id              => Next_Id (DB, Tx),
                     Name            => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("REST API")),
                     Status          => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("Design")),
                     Project_Type    => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("Service")),
                     Functions       => To_Unbounded_Wide_Wide_String
                                       (To_Wide ("JSON API, CRUD Operations,") &
                                        " Validation"),
                     Has_Project_Tools => False,
                     Has_GNAT        => True,
                     Has_GitHub      => True,
                     Has_Alire       => False));
               Raise_On_Error (Result, "sample project 5 insert failed");

               Result := Standard.Database.Transactions.Commit (Tx);
               Raise_On_Error (Result, "sample projects commit failed");
            end if;
         exception
            when others =>
               Standard.Database.Transactions.Rollback (Tx);
               raise;
         end;
      end Insert_Sample_Projects;
   begin
      App.Database.With_Database (Insert_Sample_Projects'Access);
   end Initialize;

   --  Convert project row to external project record
   function To_Project_Record (Row : Project_Row) return Project_Record is

      Result : Project_Record;
      Name_Len : constant Natural := Natural'Min (Length (Row.Name), 100);
      Status_Len : constant Natural := Natural'Min (Length (Row.Status), 50);
      Project_Type_Len : constant Natural := Natural'Min (Length (Row.Project_Type), 50);
      Functions_Len : constant Natural := Natural'Min (Length (Row.Functions), 200);
   begin
      Result.Id := Row.Id;

      --  Copy strings with bounds checking
      if Length (Row.Name) > 0 then
         Result.Name (1 .. Name_Len) :=
           To_Narrow (Slice (Row.Name, 1, Name_Len));
      end if;

      if Length (Row.Status) > 0 then
         Result.Status (1 .. Status_Len) :=
           To_Narrow (Slice (Row.Status, 1, Status_Len));
      end if;

      if Length (Row.Project_Type) > 0 then
         Result.Project_Type (1 .. Project_Type_Len) :=
           To_Narrow (Slice (Row.Project_Type, 1, Project_Type_Len));
      end if;

      if Length (Row.Functions) > 0 then
         Result.Functions (1 .. Functions_Len) :=
           To_Narrow (Slice (Row.Functions, 1, Functions_Len));
      end if;

      Result.Has_Project_Tools := Row.Has_Project_Tools;
      Result.Has_GNAT := Row.Has_GNAT;
      Result.Has_GitHub := Row.Has_GitHub;
      Result.Has_Alire := Row.Has_Alire;

      return Result;
   end To_Project_Record;

   --  Get all projects from the database
   function Get_Projects
     (Alire_Only : Boolean := False) return Project_Vectors.Vector
   is
      Result_Items : Project_Vectors.Vector;

      procedure Read_Projects (DB : in out Standard.Database.Handle) is
         Tx      : Standard.Database.Transactions.Transaction;
         Result  : Standard.Database.Status.Result;
         Cursor  : Project_Tables.Cursor;

         --  Push the authorization data scope into the query: when scoped, the
         --  database returns only Alire-tracked projects (has_alire stored as
         --  1), so out-of-scope rows never leave the database.
         Filter : constant Standard.Database.Predicates.Predicate :=
           (if Alire_Only then
              Standard.Database.Predicates.Column_Equals
                (Standard.Database.Schema.Find_Column_Position
                   (Schema, "has_alire"),
                 Standard.Database.Values.From_Integer (1))
            else Standard.Database.Predicates.True_Predicate);
      begin
         Ensure_Registered (DB);
         Standard.Database.Transactions.Begin_Read (DB, Tx);

         Result := Project_Tables.Scan (Tx, DB, Schema, Filter, Cursor);
         Raise_On_Error (Result, "projects scan failed");

         while Project_Tables.Has_Element (Cursor) loop
            declare
               Item : constant Project_Row := Project_Tables.Element (Cursor);
            begin
               Result_Items.Append (To_Project_Record (Item));
            end;

            Result := Project_Tables.Next (Tx, DB, Schema, Filter, Cursor);
            exit when not Standard.Database.Status.Is_Ok (Result);
         end loop;

         Result := Standard.Database.Transactions.Commit (Tx);
         Raise_On_Error (Result, "projects read commit failed");
      exception
         when others =>
            Standard.Database.Transactions.Rollback (Tx);
            raise;
      end Read_Projects;
   begin
      App.Database.With_Database (Read_Projects'Access);
      return Result_Items;
   end Get_Projects;

   --  Delete a project from the database
   procedure Delete_Project (Id : Natural) is

      procedure Delete_From_DB (DB : in out Standard.Database.Handle) is
         Tx     : Standard.Database.Transactions.Transaction;
         Result : Standard.Database.Status.Result;
      begin
         Ensure_Registered (DB);
         Standard.Database.Transactions.Begin_Write (DB, Tx);

         --  Delete by key (Id)
         Result := Project_Tables.Delete
           (Tx, DB, Schema, Id);

         if Standard.Database.Status.Is_Ok (Result) then
            Result := Standard.Database.Transactions.Commit (Tx);
            Raise_On_Error (Result, "projects delete commit failed");
         else
            Standard.Database.Transactions.Rollback (Tx);
            Raise_On_Error (Result, "projects delete failed");
         end if;
      end Delete_From_DB;
   begin
      App.Database.With_Database (Delete_From_DB'Access);
   end Delete_Project;

end App.Projects;

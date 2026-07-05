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

package body App.Store is
   use Ada.Strings.Wide_Wide_Unbounded;

   type Todo_Row is record
      Id    : Natural := 0;
      Title : Unbounded_Wide_Wide_String;
   end record;

   function To_Row (Item : Todo_Row) return Standard.Database.Rows.Row;
   function From_Row (Row : Standard.Database.Rows.Row) return Todo_Row;
   function Key_Of (Item : Todo_Row) return Natural;
   function Key_Value (Key : Natural) return Standard.Database.Values.Value;

   package Todo_Tables is new Standard.Database.Tables.Typed
     (Row_Type  => Todo_Row,
      Key_Type  => Natural,
      To_Row    => To_Row,
      From_Row  => From_Row,
      Key_Of    => Key_Of,
      Key_Value => Key_Value);

   Schema     : Standard.Database.Schema.Table_Schema;
   Registered : Boolean := False;

   function To_Wide (Text : String) return Wide_Wide_String is
   begin
      return Ada.Characters.Conversions.To_Wide_Wide_String (Text);
   end To_Wide;

   function To_Narrow (Text : Wide_Wide_String) return String is
   begin
      return Ada.Characters.Conversions.To_String (Text);
   end To_Narrow;

   function New_Schema return Standard.Database.Schema.Table_Schema is
      Result : Standard.Database.Schema.Table_Schema;
   begin
      Result.Name := To_Unbounded_Wide_Wide_String ("todos");
      Standard.Database.Schema.Add_Column
        (Result,
         Name        => "id",
         Kind        => Standard.Database.Types.Integer_Value,
         Nullable    => False,
         Primary_Key => True);
      Standard.Database.Schema.Add_Column
        (Result,
         Name     => "title",
         Kind     => Standard.Database.Types.Text_Value,
         Nullable => False);
      return Result;
   end New_Schema;

   function To_Row (Item : Todo_Row) return Standard.Database.Rows.Row is
      Result : Standard.Database.Rows.Row;
   begin
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Integer (Integer (Item.Id)));
      Standard.Database.Rows.Append
        (Result,
         Standard.Database.Values.From_Text (To_Wide_Wide_String (Item.Title)));
      return Result;
   end To_Row;

   function From_Row (Row : Standard.Database.Rows.Row) return Todo_Row is
   begin
      return
        (Id    => Natural (Standard.Database.Rows.Get (Row, 0).Int),
         Title => Standard.Database.Rows.Get (Row, 1).Text);
   end From_Row;

   function Key_Of (Item : Todo_Row) return Natural is
   begin
      return Item.Id;
   end Key_Of;

   function Key_Value (Key : Natural) return Standard.Database.Values.Value is
   begin
      return Standard.Database.Values.From_Integer (Integer (Key));
   end Key_Value;

   procedure Raise_On_Error
     (Result  : Standard.Database.Status.Result;
      Message : String) is
   begin
      if not Standard.Database.Status.Is_Ok (Result) then
         raise Program_Error with Message;
      end if;
   end Raise_On_Error;

   procedure Ensure_Registered (DB : in out Standard.Database.Handle) is
      Result : Standard.Database.Status.Result;
   begin
      if Registered then
         return;
      end if;

      Schema := New_Schema;
      Result := Todo_Tables.Register (DB, Schema);
      if Standard.Database.Status.Is_Ok (Result) then
         Registered := True;
         return;
      end if;

      Result := Standard.Database.Catalog.Find_By_Name ("todos", Schema);
      Raise_On_Error (Result, "todo table registration failed");
      Registered := True;
   end Ensure_Registered;

   function Next_Id
     (DB : in out Standard.Database.Handle;
      Tx : in out Standard.Database.Transactions.Transaction) return Natural
   is
      Cursor : Todo_Tables.Cursor;
      Result : Standard.Database.Status.Result;
      Next   : Natural := 1;
   begin
      Result :=
        Todo_Tables.Scan
          (Tx,
           DB,
           Schema,
           Standard.Database.Predicates.True_Predicate,
           Cursor);
      Raise_On_Error (Result, "todo id scan failed");

      while Todo_Tables.Has_Element (Cursor) loop
         declare
            Item : constant Todo_Row := Todo_Tables.Element (Cursor);
         begin
            if Item.Id >= Next then
               Next := Item.Id + 1;
            end if;
         end;

         Result :=
           Todo_Tables.Next
             (Tx,
              DB,
              Schema,
              Standard.Database.Predicates.True_Predicate,
              Cursor);
         exit when not Standard.Database.Status.Is_Ok (Result);
      end loop;

      return Next;
   end Next_Id;

   procedure Add_Todo (Title : String) is
      procedure Insert_Todo (DB : in out Standard.Database.Handle) is
         Tx     : Standard.Database.Transactions.Transaction;
         Result : Standard.Database.Status.Result;
      begin
         Ensure_Registered (DB);
         Standard.Database.Transactions.Begin_Write (DB, Tx);
         Result :=
           Todo_Tables.Insert
             (Tx,
              DB,
              Schema,
              (Id    => Next_Id (DB, Tx),
               Title => To_Unbounded_Wide_Wide_String (To_Wide (Title))));

         if Standard.Database.Status.Is_Ok (Result) then
            Result := Standard.Database.Transactions.Commit (Tx);
            Raise_On_Error (Result, "todo commit failed");
         else
            Standard.Database.Transactions.Rollback (Tx);
            Raise_On_Error (Result, "todo insert failed");
         end if;
      end Insert_Todo;
   begin
      App.Database.With_Database (Insert_Todo'Access);
   end Add_Todo;

   function Todos return Todo_Vectors.Vector is
      Result_Items : Todo_Vectors.Vector;

      procedure Read_Todos (DB : in out Standard.Database.Handle) is
         Tx      : Standard.Database.Transactions.Transaction;
         Result  : Standard.Database.Status.Result;
         Cursor  : Todo_Tables.Cursor;
      begin
         Ensure_Registered (DB);
         Standard.Database.Transactions.Begin_Read (DB, Tx);
         Result :=
           Todo_Tables.Scan
             (Tx,
              DB,
              Schema,
              Standard.Database.Predicates.True_Predicate,
              Cursor);
         Raise_On_Error (Result, "todo scan failed");

         while Todo_Tables.Has_Element (Cursor) loop
            declare
               Item : constant Todo_Row := Todo_Tables.Element (Cursor);
            begin
               Result_Items.Append (To_Narrow (To_Wide_Wide_String (Item.Title)));
            end;

            Result :=
              Todo_Tables.Next
                (Tx,
                 DB,
                 Schema,
                 Standard.Database.Predicates.True_Predicate,
                 Cursor);
            exit when not Standard.Database.Status.Is_Ok (Result);
         end loop;

         Result := Standard.Database.Transactions.Commit (Tx);
         Raise_On_Error (Result, "todo read commit failed");
      exception
         when others =>
            Standard.Database.Transactions.Rollback (Tx);
            raise;
      end Read_Todos;
   begin
      App.Database.With_Database (Read_Todos'Access);
      return Result_Items;
   exception
      when others =>
         return Todo_Vectors.Empty_Vector;
   end Todos;
end App.Store;

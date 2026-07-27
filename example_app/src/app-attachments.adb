with Ada.Streams;           use Ada.Streams;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Directories;

with Web.Multipart;

with Webfiles.Raw_Identifiers;
with Webfiles.Identifiers;
with Webfiles.Scopes;
with Webfiles.Service;
with Webfiles.Service.Lifecycle;
with Webfiles.Service.Deletion;
with Webfiles.References;
with Webfiles.Void_Results;

with Webfiles.Filenames;

with Webfiles_Storage_Local;
with Webfiles_Repository_Memory;
with Webfiles_Webframework;
with Webfiles_Webframework.Streaming;
with Webfiles_Runtime.System_Clock;
with Webfiles_Runtime.Csprng_Ids;

package body App.Attachments is

   package Raw  renames Webfiles.Raw_Identifiers;
   package Ids  renames Webfiles.Identifiers;
   package Svc  renames Webfiles.Service;
   package Life renames Webfiles.Service.Lifecycle;
   package Del  renames Webfiles.Service.Deletion;
   package Refs renames Webfiles.References;
   package Void renames Webfiles.Void_Results;

   use type Svc.Construct_Outcome;
   use type Webfiles_Storage_Local.Init_Outcome;
   use type Webfiles.Byte_Count;

   Service_Instance : Svc.Instance;
   Started          : Boolean := False;

   --  The streaming lane is not bounded by the server's request-size cap (the
   --  body is never buffered), so uploads can be much larger; the session
   --  enforces this ceiling.
   Max_Upload : constant Webfiles.Byte_Count := 64 * 1024 * 1024;

   function Sixteen (V : Stream_Element) return Stream_Element_Array is
     ([1 .. 16 => V]);

   Provider_Id : constant Ids.Provider_Id :=
     Ids.Provider_Id (Raw.From_Bytes (Sixteen (5)));
   Demo_Tenant : constant Ids.Tenant_Id :=
     Ids.Tenant_Id (Raw.From_Bytes (Sixteen (5)));
   Demo_Scope  : constant Webfiles.Scopes.Object_Scope :=
     Webfiles.Scopes.Tenant_Scope (Demo_Tenant);

   ---------------------------------------------------------------------------
   --  Catalog (protected: the server serves requests concurrently)
   ---------------------------------------------------------------------------
   type Record_Entry is record
      View      : Entry_View;
      Reference : Refs.Committed_Reference;
   end record;
   type Record_Array is array (1 .. Max_Attachments) of Record_Entry;

   function To_View (Number : Doc_Number; Name : String;
                     Size : Webfiles.Byte_Count) return Entry_View
   is
      Result : Entry_View := (Number => Number, Size => Size, others => <>);
      Len    : constant Natural := Natural'Min (Name'Length, Result.Name'Length);
   begin
      Result.Name (1 .. Len) := Name (Name'First .. Name'First + Len - 1);
      Result.Name_Length := Len;
      return Result;
   end To_View;

   protected Store is
      procedure Add (Name : String; Size : Webfiles.Byte_Count;
                     Reference : Refs.Committed_Reference; Ok : out Boolean);
      procedure Snapshot (Items : out Entry_Array; Count : out Natural);
      procedure Get (Number : Doc_Number; Found : out Boolean;
                     Reference : out Refs.Committed_Reference; View : out Entry_View);
      procedure Remove (Number : Doc_Number; Removed : out Boolean);
   private
      Entries : Record_Array;
      Used    : Natural    := 0;
      Next_No : Doc_Number := 1;
   end Store;

   protected body Store is
      procedure Add (Name : String; Size : Webfiles.Byte_Count;
                     Reference : Refs.Committed_Reference; Ok : out Boolean) is
      begin
         if Used >= Max_Attachments then
            Ok := False;
            return;
         end if;
         Used := Used + 1;
         Entries (Used) := (View => To_View (Next_No, Name, Size),
                            Reference => Reference);
         Next_No := Next_No + 1;
         Ok := True;
      end Add;

      procedure Snapshot (Items : out Entry_Array; Count : out Natural) is
      begin
         Count := 0;
         for I in 1 .. Used loop
            exit when I > Items'Length;
            Count := Count + 1;
            Items (Items'First + I - 1) := Entries (I).View;
         end loop;
      end Snapshot;

      procedure Get (Number : Doc_Number; Found : out Boolean;
                     Reference : out Refs.Committed_Reference;
                     View : out Entry_View) is
      begin
         Found := False;
         for I in 1 .. Used loop
            if Entries (I).View.Number = Number then
               Found     := True;
               Reference := Entries (I).Reference;
               View      := Entries (I).View;
               return;
            end if;
         end loop;
      end Get;

      procedure Remove (Number : Doc_Number; Removed : out Boolean) is
      begin
         Removed := False;
         for I in 1 .. Used loop
            if Entries (I).View.Number = Number then
               for J in I .. Used - 1 loop
                  Entries (J) := Entries (J + 1);
               end loop;
               Used    := Used - 1;
               Removed := True;
               return;
            end if;
         end loop;
      end Remove;
   end Store;

   ---------------------------------------------------------------------------
   --  Composition
   ---------------------------------------------------------------------------
   procedure Initialize (Data_Root : String; Status : out Init_Status) is
      Provider_Ptr : Svc.Provider_Access;
      Init_Out     : Webfiles_Storage_Local.Init_Outcome;
      Cons         : Svc.Construct_Outcome;
   begin
      if Started then
         Status := Ready;
         return;
      end if;
      begin
         Ada.Directories.Create_Path (Data_Root);
      exception
         when others =>
            Status := Storage_Error;
            return;
      end;

      Provider_Ptr := new Webfiles_Storage_Local.Provider;
      Webfiles_Storage_Local.Open
        (Root => Data_Root, Id => Provider_Id,
         Result => Webfiles_Storage_Local.Provider (Provider_Ptr.all),
         Outcome => Init_Out);
      if Init_Out /= Webfiles_Storage_Local.Ok then
         Status := Storage_Error;
         return;
      end if;

      Svc.Construct
        (Repository  => new Webfiles_Repository_Memory.Repository'
                          (Webfiles_Repository_Memory.Create),
         Provider    => Provider_Ptr,
         Provider_Id => Provider_Id,
         Clock       => new Webfiles_Runtime.System_Clock.Clock,
         Generator   => new Webfiles_Runtime.Csprng_Ids.Generator,
         Result      => Service_Instance, Outcome => Cons);
      if Cons /= Svc.Ok then
         Status := Service_Error;
         return;
      end if;
      Started := True;
      Status  := Ready;
   end Initialize;

   function Fresh_Operation return Ids.Operation_Id is
      R : Raw.Raw_Id;
   begin
      Raw.Next (Svc.Generator (Service_Instance).all, R);
      return Ids.Operation_Id (R);
   end Fresh_Operation;

   ---------------------------------------------------------------------------
   --  Operations
   ---------------------------------------------------------------------------
   procedure List (Items : out Entry_Array; Count : out Natural) is
   begin
      Store.Snapshot (Items, Count);
   end List;

   procedure Upload_From
     (Request : Web.Request.Request_Type;
      Actor   : String;
      Ok      : out Boolean)
   is
      pragma Unreferenced (Actor);
      Body_Text : constant String := Web.Request.Request_Body (Request);
      Content_T : constant String := Web.Request.Header (Request, "Content-Type");
      Boundary  : constant String := Web.Multipart.Boundary_Of (Content_T);
      Parts     : Web.Multipart.Part_Array (1 .. 32);
      Count     : Natural;
      Status    : Web.Multipart.Parse_Status;
      Filename  : Unbounded_String;
      File_Size : Webfiles.Byte_Count := 0;
      use type Web.Multipart.Parse_Status;
      use type Web.Multipart.Part_Kind;
   begin
      Ok := False;
      if Boundary = "" then
         return;
      end if;
      --  Read the first file part's name and size for the catalog; the bridge
      --  re-parses to stream the bytes.
      Web.Multipart.Parse (Body_Text, Boundary, Parts, Count, Status);
      if Status /= Web.Multipart.Ok then
         return;
      end if;
      for I in 1 .. Count loop
         if Parts (I).Kind = Web.Multipart.File_Part then
            Filename := Parts (I).Filename;
            if Parts (I).Last >= Parts (I).First then
               File_Size := Webfiles.Byte_Count (Parts (I).Last - Parts (I).First + 1);
            end if;
            exit;
         end if;
      end loop;

      declare
         Found     : Boolean;
         Staged    : Life.Staged_Results.Result;
         Committed : Life.Committed_Results.Result;
         Added     : Boolean;
         Display   : constant String :=
           (if Length (Filename) = 0 then "attachment" else To_String (Filename));
      begin
         Webfiles_Webframework.Ingest_First_File
           (Service => Service_Instance, Scope => Demo_Scope,
            Request => Request, Max_Size => Max_Upload,
            Operation => Fresh_Operation, Found => Found, Result => Staged);
         if not Found or else not Life.Staged_Results.Is_Ok (Staged) then
            return;
         end if;
         Life.Commit (Service_Instance, Staged.Value, Committed);
         if not Life.Committed_Results.Is_Ok (Committed) then
            return;
         end if;
         Store.Add (Display, File_Size, Committed.Value, Added);
         Ok := Added;
      end;
   end Upload_From;

   procedure Stream_Upload
     (Body_R   : in out Web.Http_Body.Reader;
      Boundary : String;
      Ok       : out Boolean)
   is
      Found     : Boolean;
      Filename  : Webfiles.Filenames.Display_Filename;
      Size      : Webfiles.Byte_Count;
      Staged    : Life.Staged_Results.Result;
      Committed : Life.Committed_Results.Result;
      Added     : Boolean;
   begin
      Ok := False;
      Webfiles_Webframework.Streaming.Stream_First_File
        (Service   => Service_Instance,
         Scope     => Demo_Scope,
         Body_R    => Body_R,
         Boundary  => Boundary,
         Max_Size  => Max_Upload,
         Operation => Fresh_Operation,
         Found     => Found,
         Filename  => Filename,
         Size      => Size,
         Result    => Staged);
      if not Found or else not Life.Staged_Results.Is_Ok (Staged) then
         return;
      end if;
      Life.Commit (Service_Instance, Staged.Value, Committed);
      if not Life.Committed_Results.Is_Ok (Committed) then
         return;
      end if;
      declare
         Name : constant String := Webfiles.Filenames.Display.Octets (Filename);
      begin
         Store.Add
           ((if Name = "" then "attachment" else Name),
            Size, Committed.Value, Added);
         Ok := Added;
      end;
   end Stream_Upload;

   function Download (Number : Doc_Number) return Web.Response.Response_Type is
      Found     : Boolean;
      Reference : Refs.Committed_Reference;
      View      : Entry_View;
   begin
      Store.Get (Number, Found, Reference, View);
      if not Found then
         return Web.Response.Not_Found;
      end if;
      return Webfiles_Webframework.Download
        (Service_Instance, Reference, View.Name (1 .. View.Name_Length));
   end Download;

   procedure Delete (Number : Doc_Number) is
      Found     : Boolean;
      Reference : Refs.Committed_Reference;
      View      : Entry_View;
      R1, R2    : Void.Void_Result;
      Removed   : Boolean;
   begin
      Store.Get (Number, Found, Reference, View);
      if Found then
         Del.Delete_Logical (Service_Instance, Reference, R1);
         Del.Delete_Physical
           (Service_Instance, Refs.Scope_Of (Reference),
            Refs.Object_Of (Reference), R2);
         Store.Remove (Number, Removed);
      end if;
   end Delete;

end App.Attachments;

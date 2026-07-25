with Ada.Finalization;
with Ada.Strings.Bounded;
with Web.Binding.Multipart;
with Web.Binding.Diagnostics;

--  Files and Uploads adapter.
--
--  A narrow, explicit contract to whatever backend stages uploaded files (no
--  such sibling exists yet, so the contract is defined here with an in-memory
--  implementation in the child Memory package as the default backend and test
--  double -- binding never embeds a real storage subsystem). A backend
--  implements Upload_Sink (Begin_Upload / Write_Chunk / Finish_Upload /
--  Abort_Upload); the binding layer streams a multipart part's body into it
--  chunk by chunk (never buffering the whole file, invariant BIND-009) and hands
--  back an opaque Upload_Handle, never a path.
--
--  An Upload_Session is a controlled, request-scoped owner: on Finalize (scope
--  exit) or Discard it aborts every staged-but-uncommitted upload, so a failed
--  bind cleans up deterministically and handles never escape (BIND-010).
package Web.Binding.Uploads is

   Max_Meta    : constant := 256;
   Max_Uploads : constant := 64;

   package Meta_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Meta);

   --  Metadata captured for a staged upload -- never a filesystem path.
   type Upload_Meta is record
      Filename     : Meta_Strings.Bounded_String;  --  untrusted client name
      Content_Type : Meta_Strings.Bounded_String;
      Byte_Count   : Web.Binding.Byte_Count := 0;
      Checksum     : Meta_Strings.Bounded_String;   --  backend-supplied
   end record;

   --  The staging backend contract.
   type Upload_Sink is limited interface;

   --  Begin staging a file; Ref identifies it to later calls.
   --  @param Sink The backend.
   --  @param Filename The client filename (metadata only).
   --  @param Content_Type The part content type.
   --  @param Ref A backend reference for the staged upload.
   --  @param Ok False if the backend refused.
   procedure Begin_Upload
     (Sink         : in out Upload_Sink;
      Filename     : String;
      Content_Type : String;
      Ref          : out Natural;
      Ok           : out Boolean) is abstract;

   --  Append a chunk of file bytes.
   --  @param Sink The backend.
   --  @param Ref The staged upload.
   --  @param Data The bytes.
   --  @param Ok False on a write failure.
   procedure Write_Chunk
     (Sink : in out Upload_Sink;
      Ref  : Natural;
      Data : String;
      Ok   : out Boolean) is abstract;

   --  Finish staging; yields the captured metadata.
   --  @param Sink The backend.
   --  @param Ref The staged upload.
   --  @param Meta The captured metadata.
   --  @param Ok False if finishing failed.
   procedure Finish_Upload
     (Sink : in out Upload_Sink;
      Ref  : Natural;
      Meta : out Upload_Meta;
      Ok   : out Boolean) is abstract;

   --  Abort staging and release any temporary storage.
   --  @param Sink The backend.
   --  @param Ref The staged upload.
   procedure Abort_Upload
     (Sink : in out Upload_Sink; Ref : Natural) is abstract;

   type Upload_Handle is private;

   Null_Handle : constant Upload_Handle;

   type Upload_Status is
     (Upload_Ok,
      Sink_Rejected,
      Upload_Too_Large,
      Aggregate_Too_Large,
      Too_Many_Uploads);

   type Upload_Session (Sink : access Upload_Sink'Class) is
     new Ada.Finalization.Limited_Controlled with private;

   --  Set the per-upload and aggregate byte limits.
   --  @param Session The session.
   --  @param Max_Per_Upload The per-file limit.
   --  @param Max_Total The aggregate limit across all uploads.
   procedure Configure
     (Session        : in out Upload_Session;
      Max_Per_Upload : Web.Binding.Byte_Count;
      Max_Total      : Web.Binding.Byte_Count);

   --  Attach a diagnostics sink; the session emits an Upload_Aborted event when
   --  it aborts a staged upload (including on failed-bind cleanup).
   --  @param Session The session.
   --  @param Sink The diagnostics sink.
   --  @param Correlation The request correlation id.
   --  @param Route The route id.
   procedure Attach_Diagnostics
     (Session     : in out Upload_Session;
      Sink        : access Web.Binding.Diagnostics.Sink'Class;
      Correlation : String := "";
      Route       : String := "");

   --  Stream a multipart part's body into a new staged upload. Never buffers the
   --  whole file; enforces the per-upload and aggregate limits; aborts the
   --  upload on any failure.
   --  @param Session The session.
   --  @param Reader The multipart reader positioned on a file part's body.
   --  @param Info The part's metadata.
   --  @param Handle The staged upload handle (Null_Handle on failure).
   --  @param Status The outcome.
   procedure Stream_Part
     (Session : in out Upload_Session;
      Reader  : in out Web.Binding.Multipart.Multipart_Reader;
      Info    : Web.Binding.Multipart.Part_Info;
      Handle  : out Upload_Handle;
      Status  : out Upload_Status);

   --  The metadata of a staged upload.
   --  @param Session The session.
   --  @param Handle The upload handle.
   --  @return The metadata.
   function Handle_Meta
     (Session : Upload_Session; Handle : Upload_Handle) return Upload_Meta;

   --  The number of staged uploads.
   --  @param Session The session.
   --  @return The count.
   function Count (Session : Upload_Session) return Natural;

   --  Commit all staged uploads: they will not be aborted on Discard/Finalize.
   --  @param Session The session.
   procedure Commit (Session : in out Upload_Session);

   --  Abort every staged-but-uncommitted upload now.
   --  @param Session The session.
   procedure Discard (Session : in out Upload_Session);

private

   type Upload_Handle is record
      Slot : Natural := 0;
   end record;

   Null_Handle : constant Upload_Handle := (Slot => 0);

   type Slot_Record is record
      Ref       : Natural := 0;
      Bytes     : Web.Binding.Byte_Count := 0;
      Active    : Boolean := False;
      Committed : Boolean := False;
      Meta      : Upload_Meta;
   end record;

   type Slot_Array is array (1 .. Max_Uploads) of Slot_Record;

   type Upload_Session (Sink : access Upload_Sink'Class) is
     new Ada.Finalization.Limited_Controlled with record
      Slots     : Slot_Array;
      Used      : Natural := 0;
      Total     : Web.Binding.Byte_Count := 0;
      Max_Per   : Web.Binding.Byte_Count := Web.Binding.Byte_Count'Last;
      Max_Total : Web.Binding.Byte_Count := Web.Binding.Byte_Count'Last;
      Diag      : access Web.Binding.Diagnostics.Sink'Class := null;
      Corr      : Meta_Strings.Bounded_String;
      Route     : Meta_Strings.Bounded_String;
   end record;

   overriding procedure Finalize (Session : in out Upload_Session);

end Web.Binding.Uploads;

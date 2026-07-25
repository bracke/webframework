--  In-memory upload sink: the default backend and the test double.
--
--  Counts bytes and computes a rolling checksum without retaining file content,
--  and can inject a begin / write / finish failure so the upload driver's abort
--  and cleanup paths are exercised deterministically. Inspection functions let
--  tests confirm that a failed or uncommitted upload was aborted.
package Web.Binding.Uploads.Memory is

   type Fault_Kind is (No_Fault, Fail_Begin, Fail_Write, Fail_Finish);

   Max_Staged : constant := 64;

   type Memory_Sink is limited new Upload_Sink with private;

   --  Configure an injected fault.
   --  @param Sink The sink.
   --  @param Inject The fault to inject.
   --  @param Fail_After For Fail_Write, the number of successful writes first.
   procedure Configure
     (Sink : in out Memory_Sink; Inject : Fault_Kind; Fail_After : Natural := 0);

   --  Bytes written to a staged upload.
   --  @param Sink The sink.
   --  @param Ref The staged reference.
   --  @return The byte count.
   function Bytes_Of
     (Sink : Memory_Sink; Ref : Natural) return Web.Binding.Byte_Count;

   --  Whether a staged upload was aborted.
   --  @param Sink The sink.
   --  @param Ref The staged reference.
   --  @return True if aborted.
   function Aborted (Sink : Memory_Sink; Ref : Natural) return Boolean;

   --  Whether a staged upload was finished.
   --  @param Sink The sink.
   --  @param Ref The staged reference.
   --  @return True if finished.
   function Finished (Sink : Memory_Sink; Ref : Natural) return Boolean;

   overriding procedure Begin_Upload
     (Sink         : in out Memory_Sink;
      Filename     : String;
      Content_Type : String;
      Ref          : out Natural;
      Ok           : out Boolean);

   overriding procedure Write_Chunk
     (Sink : in out Memory_Sink;
      Ref  : Natural;
      Data : String;
      Ok   : out Boolean);

   overriding procedure Finish_Upload
     (Sink : in out Memory_Sink;
      Ref  : Natural;
      Meta : out Upload_Meta;
      Ok   : out Boolean);

   overriding procedure Abort_Upload
     (Sink : in out Memory_Sink; Ref : Natural);

private

   type Staged is record
      Filename     : Meta_Strings.Bounded_String;
      Content_Type : Meta_Strings.Bounded_String;
      Bytes        : Web.Binding.Byte_Count := 0;
      Sum          : Long_Long_Integer := 0;
      Finished_F   : Boolean := False;
      Aborted_F    : Boolean := False;
   end record;

   type Staged_Array is array (1 .. Max_Staged) of Staged;

   type Memory_Sink is limited new Upload_Sink with record
      Items      : Staged_Array;
      Used       : Natural := 0;
      Inject     : Fault_Kind := No_Fault;
      Fail_After : Natural := 0;
      Writes     : Natural := 0;
   end record;

end Web.Binding.Uploads.Memory;

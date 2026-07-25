with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Streams.Memory;
with Web.Binding.Multipart;
with Web.Binding.Uploads;
with Web.Binding.Uploads.Memory;

package body Web_Binding_Upload_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;

   package Mem renames Web.Binding.Streams.Memory;
   package MP renames Web.Binding.Multipart;
   package UP renames Web.Binding.Uploads;
   package Sink_Pkg renames Web.Binding.Uploads.Memory;
   use type UP.Upload_Status;

   NL : constant String := [Character'Val (13), Character'Val (10)];

   File_Body : constant String :=
     "--BND" & NL
     & "Content-Disposition: form-data; name=""file""; filename=""a.bin""" & NL
     & "Content-Type: application/octet-stream" & NL & NL
     & "HELLOWORLD" & NL
     & "--BND--" & NL;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("upload stream", Test_Stream'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("upload limits", Test_Limits'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("upload sink failure", Test_Sink_Failure'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("upload cleanup", Test_Cleanup'Access));
   end Add_Tests;

   procedure Test_Stream (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Sink      : aliased Sink_Pkg.Memory_Sink;
      St        : UP.Upload_Status := UP.Sink_Rejected;
      Bytes     : Byte_Count := 0;
      Cksum_Len : Natural := 0;
   begin
      declare
         S       : aliased Mem.Memory_Stream := Mem.Create (File_Body);
         R       : MP.Multipart_Reader (S'Access);
         Session : UP.Upload_Session (Sink'Access);
         Info    : MP.Part_Info;
         Avail   : Boolean;
         H       : UP.Upload_Handle;
      begin
         MP.Start (R, "BND");
         MP.Next_Part (R, Info, Avail);
         UP.Stream_Part (Session, R, Info, H, St);
         if St = UP.Upload_Ok then
            declare
               M : constant UP.Upload_Meta := UP.Handle_Meta (Session, H);
            begin
               Bytes := M.Byte_Count;
               Cksum_Len := UP.Meta_Strings.Length (M.Checksum);
            end;
            UP.Commit (Session);
         end if;
      end;
      Assert (St = UP.Upload_Ok, "upload streamed");
      Assert (Bytes = 10, "ten bytes streamed");
      Assert (Cksum_Len = 8, "checksum captured");
      Assert (Sink_Pkg.Finished (Sink, 1), "sink finished the upload");
      Assert (not Sink_Pkg.Aborted (Sink, 1), "committed upload not aborted");
   end Test_Stream;

   --  Stream the file part with the given limits; report status and whether the
   --  sink's first upload was aborted.
   procedure Run
     (Max_Per : Byte_Count;
      Max_Total : Byte_Count;
      Inject : Sink_Pkg.Fault_Kind;
      St : out UP.Upload_Status;
      Aborted : out Boolean)
   is
      Sink : aliased Sink_Pkg.Memory_Sink;
   begin
      Sink_Pkg.Configure (Sink, Inject);
      declare
         S       : aliased Mem.Memory_Stream := Mem.Create (File_Body, 3);
         R       : MP.Multipart_Reader (S'Access);
         Session : UP.Upload_Session (Sink'Access);
         Info    : MP.Part_Info;
         Avail   : Boolean;
         H       : UP.Upload_Handle;
      begin
         UP.Configure (Session, Max_Per, Max_Total);
         MP.Start (R, "BND");
         MP.Next_Part (R, Info, Avail);
         UP.Stream_Part (Session, R, Info, H, St);
         UP.Commit (Session);  --  commit so cleanup does not confound the check
      end;
      Aborted := Sink_Pkg.Aborted (Sink, 1);
   end Run;

   procedure Test_Limits (Item : in out Fixture) is
      pragma Unreferenced (Item);
      St : UP.Upload_Status;
      Aborted : Boolean;
   begin
      Run (Max_Per => 3, Max_Total => Byte_Count'Last,
           Inject => Sink_Pkg.No_Fault, St => St, Aborted => Aborted);
      Assert (St = UP.Upload_Too_Large, "per-upload limit");
      Assert (Aborted, "over-size upload aborted");

      Run (Max_Per => Byte_Count'Last, Max_Total => 3,
           Inject => Sink_Pkg.No_Fault, St => St, Aborted => Aborted);
      Assert (St = UP.Aggregate_Too_Large, "aggregate limit");
      Assert (Aborted, "aggregate-exceeding upload aborted");
   end Test_Limits;

   procedure Test_Sink_Failure (Item : in out Fixture) is
      pragma Unreferenced (Item);
      St : UP.Upload_Status;
      Aborted : Boolean;
   begin
      Run (Max_Per => Byte_Count'Last, Max_Total => Byte_Count'Last,
           Inject => Sink_Pkg.Fail_Write, St => St, Aborted => Aborted);
      Assert (St = UP.Sink_Rejected, "sink write failure rejected");
      Assert (Aborted, "failed upload aborted");
   end Test_Sink_Failure;

   procedure Test_Cleanup (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Sink : aliased Sink_Pkg.Memory_Sink;
      St   : UP.Upload_Status := UP.Sink_Rejected;
   begin
      declare
         S       : aliased Mem.Memory_Stream := Mem.Create (File_Body);
         R       : MP.Multipart_Reader (S'Access);
         Session : UP.Upload_Session (Sink'Access);
         Info    : MP.Part_Info;
         Avail   : Boolean;
         H       : UP.Upload_Handle;
      begin
         MP.Start (R, "BND");
         MP.Next_Part (R, Info, Avail);
         UP.Stream_Part (Session, R, Info, H, St);
         --  Deliberately no Commit: the session must abort on scope exit.
      end;
      Assert (St = UP.Upload_Ok, "streamed before scope exit");
      Assert (Sink_Pkg.Aborted (Sink, 1),
              "uncommitted upload aborted on session finalization");
   end Test_Cleanup;

end Web_Binding_Upload_Tests;

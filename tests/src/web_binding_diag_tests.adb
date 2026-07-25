with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Errors;
with Web.Binding.Results;
with Web.Binding.Requests;
with Web.Binding.Diagnostics;
with Web.Binding.Diagnostics.Recording;
with Web.Binding.Streams.Memory;
with Web.Binding.Multipart;
with Web.Binding.Uploads;
with Web.Binding.Uploads.Memory;

package body Web_Binding_Diag_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;

   package Diag renames Web.Binding.Diagnostics;
   package Rec_Pkg renames Web.Binding.Diagnostics.Recording;
   package Int_Results is new Web.Binding.Results (Integer);
   package Mem renames Web.Binding.Streams.Memory;
   package MP renames Web.Binding.Multipart;
   package UP renames Web.Binding.Uploads;
   package USink_Pkg renames Web.Binding.Uploads.Memory;

   use type Diag.Event_Kind;
   use type Diag.Limit_Category;

   procedure Cap_Ok (Value : Integer) is null;
   procedure Cap_Err
     (Class : Web.Binding.Requests.Failure_Class; Errors : Error_Collection)
      is null;

   procedure Do_Dispatch is new Web.Binding.Requests.Dispatch
     (Integer, Int_Results, Cap_Ok, Cap_Err);

   --  A session stores its sink, so the sink must outlive it: use a library-level
   --  recorder (as a real application's logger would be).
   Upload_Rec : aliased Rec_Pkg.Recorder;

   NL : constant String := [Character'Val (13), Character'Val (10)];
   File_Body : constant String :=
     "--BND" & NL
     & "Content-Disposition: form-data; name=""f""; filename=""a.bin""" & NL
     & NL & "DATA" & NL & "--BND--" & NL;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("diag dispatch events", Test_Dispatch_Events'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("diag upload event", Test_Upload_Event'Access));
   end Add_Tests;

   procedure Test_Dispatch_Events (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Rec  : aliased Rec_Pkg.Recorder;
      Errs : Error_Collection := Empty_Collection;
   begin
      --  Success.
      Do_Dispatch (Int_Results.Make_Success (1), Sink => Rec'Access,
                   Correlation => "c1", Route => "r1");
      Assert (Rec_Pkg.Count (Rec) = 1, "one event");
      Assert (Rec_Pkg.Get (Rec, 1).Kind = Diag.Bind_Succeeded, "succeeded event");
      Assert (Diag.Text_Strings.To_String (Rec_Pkg.Get (Rec, 1).Correlation) = "c1",
              "correlation carried");

      --  Failure with a size error on a secret-named field.
      Append (Errs, Make_Error
                (Body_Too_Large, Append_Field (Rooted (Structured_Body), "password"),
                 Structured_Body));
      Do_Dispatch (Int_Results.Make_Failure (Errs), Sink => Rec'Access,
                   Correlation => "c2", Route => "r2");
      declare
         E : constant Diag.Event := Rec_Pkg.Get (Rec, 2);
      begin
         Assert (E.Kind = Diag.Bind_Failed, "failed event");
         Assert (E.Error = Body_Too_Large and then E.Error_Count = 1, "error id + count");
         Assert (E.Limit = Diag.Body_Size, "limit category");
         --  The path is the redacted structure only -- a name, never a value.
         Assert (Diag.Path_Strings.To_String (E.Path) = "body.password",
                 "redacted path, no raw value");
      end;
   end Test_Dispatch_Events;

   procedure Test_Upload_Event (Item : in out Fixture) is
      pragma Unreferenced (Item);
      USink : aliased USink_Pkg.Memory_Sink;
      Aborted_Seen : Boolean := False;
   begin
      Rec_Pkg.Clear (Upload_Rec);
      declare
         S       : aliased Mem.Memory_Stream := Mem.Create (File_Body);
         R       : MP.Multipart_Reader (S'Access);
         Session : UP.Upload_Session (USink'Access);
         Info    : MP.Part_Info;
         Avail   : Boolean;
         H       : UP.Upload_Handle;
         St      : UP.Upload_Status;
      begin
         UP.Attach_Diagnostics (Session, Upload_Rec'Access, "c3", "r3");
         MP.Start (R, "BND");
         MP.Next_Part (R, Info, Avail);
         UP.Stream_Part (Session, R, Info, H, St);
         --  No Commit: the session aborts the staged upload on scope exit.
      end;
      for I in 1 .. Rec_Pkg.Count (Upload_Rec) loop
         if Rec_Pkg.Get (Upload_Rec, I).Kind = Diag.Upload_Aborted
           and then Diag.Text_Strings.To_String
                      (Rec_Pkg.Get (Upload_Rec, I).Correlation) = "c3"
         then
            Aborted_Seen := True;
         end if;
      end loop;
      Assert (Aborted_Seen, "upload-aborted event emitted on cleanup");
   end Test_Upload_Event;

end Web_Binding_Diag_Tests;

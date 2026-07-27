with Ada.Command_Line;
with Ada.Text_IO;

with Web.Request;
with Web.Response;
with Web.Context;

with App.Attachments;
with App.Pages;
with App.Runtime;
with App.Csrf;

--  In-process integration test for the example app's attachments feature. It
--  drives the real page handlers (App.Pages.Upload_Attachment / Download /
--  Delete) with genuine sessions and CSRF tokens -- no socket -- proving the
--  webfiles subsystem is wired end to end: multipart upload -> stage -> commit
--  -> durable storage, list, download (bytes round-trip from disk), CSRF
--  rejection, and two-phase delete. The GET page (which renders templates from
--  disk) is exercised separately by app_http_tests / manual runs; here the data
--  path is what matters.
procedure App_Attachments_Tests is

   use Ada.Text_IO;

   CRLF     : constant String := ASCII.CR & ASCII.LF;
   Boundary : constant String := "BND";

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Check (Condition : Boolean; Label : String) is
   begin
      if Condition then
         Passed := Passed + 1;
         Put_Line ("OK   " & Label);
      else
         Failed := Failed + 1;
         Put_Line ("FAIL " & Label);
      end if;
   end Check;

   function Upload_Body (Token, Filename, Content : String) return String is
     ("--" & Boundary & CRLF
      & "Content-Disposition: form-data; name=""" & App.Csrf.Field & """" & CRLF
      & CRLF & Token & CRLF
      & "--" & Boundary & CRLF
      & "Content-Disposition: form-data; name=""document""; filename="""
      & Filename & """" & CRLF
      & "Content-Type: text/plain" & CRLF & CRLF
      & Content & CRLF
      & "--" & Boundary & "--" & CRLF);

   function Multipart_Upload
     (Sid, Token, Filename, Content : String) return Web.Request.Request_Type
   is
      Req : Web.Request.Request_Type :=
        Web.Request.Create ("POST", "/attachments/upload", "",
                            Upload_Body (Token, Filename, Content));
   begin
      Web.Request.Set_Header
        (Req, "Content-Type", "multipart/form-data; boundary=" & Boundary);
      Web.Request.Set_Header (Req, "Cookie", "wf_session=" & Sid);
      return Req;
   end Multipart_Upload;

   Ctx    : constant Web.Context.Request_Context := Web.Context.New_Context;
   Status : App.Attachments.Init_Status;
   use type App.Attachments.Init_Status;
begin
   App.Attachments.Initialize ("attach_test_store", Status);
   Check (Status = App.Attachments.Ready, "attachments service initializes");
   if Status /= App.Attachments.Ready then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Sid   : constant String :=
        App.Runtime.Find_Or_Create_Session (Web.Request.Create ("GET", "/"));
      Token : constant String := App.Csrf.Token (Sid);
      Resp  : Web.Response.Response_Type;
   begin
      --  Upload with a valid token.
      Resp := App.Pages.Upload_Attachment
        (Multipart_Upload (Sid, Token, "notes.txt", "hello attachment"), Ctx);
      Check (Web.Response.Status (Resp) = 303, "upload commits and redirects");

      --  It appears in the catalog.
      declare
         Items : App.Attachments.Entry_Array (1 .. App.Attachments.Max_Attachments);
         Count : Natural;
      begin
         App.Attachments.List (Items, Count);
         Check (Count = 1
                and then Items (1).Name (1 .. Items (1).Name_Length) = "notes.txt",
                "the committed attachment is listed");
      end;

      --  Download streams the bytes back from disk.
      declare
         Get_Req : Web.Request.Request_Type :=
           Web.Request.Create ("GET", "/attachments/download", "doc=1", "");
      begin
         Web.Request.Set_Header (Get_Req, "Cookie", "wf_session=" & Sid);
         Resp := App.Pages.Download_Attachment (Get_Req, Ctx);
         Check (Web.Response.Status (Resp) = 200
                and then Web.Response.Content_Body (Resp) = "hello attachment",
                "download returns the stored bytes (durable round-trip)");
      end;

      --  A wrong CSRF token is refused.
      Resp := App.Pages.Upload_Attachment
        (Multipart_Upload (Sid, "deadbeef", "evil.txt", "nope"), Ctx);
      Check (Web.Response.Status (Resp) = 403, "upload with a bad csrf is 403");

      --  Delete, then the catalog is empty again.
      declare
         Del_Req : Web.Request.Request_Type :=
           Web.Request.Create ("POST", "/attachments/delete", "",
                              "doc=1&" & App.Csrf.Field & "=" & Token);
         Items : App.Attachments.Entry_Array (1 .. App.Attachments.Max_Attachments);
         Count : Natural;
      begin
         Web.Request.Set_Header
           (Del_Req, "Content-Type", "application/x-www-form-urlencoded");
         Web.Request.Set_Header (Del_Req, "Cookie", "wf_session=" & Sid);
         Resp := App.Pages.Delete_Attachment (Del_Req, Ctx);
         Check (Web.Response.Status (Resp) = 303, "delete redirects");
         App.Attachments.List (Items, Count);
         Check (Count = 0, "the deleted attachment is gone from the catalog");
      end;
   end;

   Put_Line ("");
   Put_Line ("passed:" & Passed'Image & "  failed:" & Failed'Image);
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end App_Attachments_Tests;

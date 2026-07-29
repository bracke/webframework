with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Web.Request;
with Web.Response;
with Web.Context;

with App.Notifications;
with App.Smtp_Catcher;
with App.Pages;
with App.Runtime;
with App.Csrf;

--  In-process integration test for the example app's email-notification feature.
--  It drives the real POST handler (App.Pages.Send_Email_Demo) with a genuine
--  session and CSRF token -- no HTTP socket for the request -- and asserts that
--  the message travelled the FULL path end to end: notification -> render
--  (notifications_templates) -> notifications_email -> smtplib -> a real TCP
--  socket -> the in-process SMTP catcher, which captured the exact RFC 5322
--  bytes on the wire (Subject / To / body all present).
procedure App_Email_Tests is

   use Ada.Text_IO;

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

   function Contains (Haystack, Needle : String) return Boolean is
     (Ada.Strings.Fixed.Index (Haystack, Needle) > 0);

   Catcher_Status : App.Smtp_Catcher.Start_Status;
   Notif_Status   : App.Notifications.Init_Status;
   Ctx            : constant Web.Context.Request_Context := Web.Context.New_Context;
   use type App.Smtp_Catcher.Start_Status;
   use type App.Notifications.Init_Status;
begin
   App.Smtp_Catcher.Start (Catcher_Status);
   Check (Catcher_Status /= App.Smtp_Catcher.Bind_Error,
          "SMTP catcher binds 127.0.0.1:"
          & Ada.Strings.Fixed.Trim (Positive'Image (App.Smtp_Catcher.Port),
                                     Ada.Strings.Both));
   App.Notifications.Initialize (Notif_Status);
   Check (Notif_Status = App.Notifications.Ready,
          "notifications engine composes (store/clock/ids/resolver/renderer/"
          & "provider)");
   if Catcher_Status = App.Smtp_Catcher.Bind_Error
     or else Notif_Status /= App.Notifications.Ready
   then
      Put_Line ("     init status = "
                & App.Notifications.Init_Status'Image (Notif_Status));
      App.Smtp_Catcher.Stop;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Sid   : constant String :=
        App.Runtime.Find_Or_Create_Session (Web.Request.Create ("GET", "/"));
      Token : constant String := App.Csrf.Token (Sid);
      Body_Text : constant String :=
        App.Csrf.Field & "=" & Token
        & "&to=alice@example.com"
        & "&subject=Hello"
        & "&message=It+works+end+to+end";
      Req  : Web.Request.Request_Type :=
        Web.Request.Create ("POST", "/email-demo/send", "", Body_Text);
      Resp : Web.Response.Response_Type;
      Before : constant Natural := App.Smtp_Catcher.Count;
   begin
      Web.Request.Set_Header
        (Req, "Content-Type", "application/x-www-form-urlencoded");
      Web.Request.Set_Header (Req, "Cookie", "wf_session=" & Sid);

      Resp := App.Pages.Send_Email_Demo (Req, Ctx);
      Check (Web.Response.Status (Resp) = 303,
             "the send handler accepts and redirects (303)");

      --  Exactly one new message reached the catcher.
      Check (App.Smtp_Catcher.Count = Before + 1,
             "the catcher captured exactly one new message");

      if App.Smtp_Catcher.Count = 0 then
         App.Smtp_Catcher.Stop;
         Put_Line ("");
         Put_Line ("passed:" & Passed'Image & "  failed:" & Failed'Image);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Mail  : App.Smtp_Catcher.Captured_Mail;
         Found : Boolean;
      begin
         App.Smtp_Catcher.Get (App.Smtp_Catcher.Count, Mail, Found);
         Check (Found, "the captured message is retrievable");
         declare
            Raw : constant String := To_String (Mail.Raw_Message);
         begin
            Check (Contains (Raw, "Subject: Hello"),
                   "the raw RFC 5322 bytes carry Subject: Hello");
            Check (Contains (Raw, "alice@example.com"),
                   "the raw message is addressed To alice@example.com");
            Check (Contains (Raw, "It works end to end"),
                   "the message body text was transmitted");
            Check (Contains (To_String (Mail.Envelope_To), "alice@example.com"),
                   "the SMTP envelope RCPT TO is the target address");
            Check (Contains (To_String (Mail.Envelope_From), "demo@example-app.local"),
                   "the SMTP envelope MAIL FROM is the resolved sender");
         end;
      end;

      --  The send-result summary reflects the delivery.
      declare
         R : constant App.Notifications.Send_Result := App.Notifications.Last_Send;
         use type App.Notifications.Send_Phase;
      begin
         Check (R.Created and then R.Reached_Catcher,
                "the send-result summary reports created + reached-catcher");
         Check (R.Phase = App.Notifications.Delivered_Attempt,
                "the send-result phase is Delivered_Attempt");
      end;
   end;

   App.Smtp_Catcher.Stop;

   Put_Line ("");
   Put_Line ("passed:" & Passed'Image & "  failed:" & Failed'Image);
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end App_Email_Tests;

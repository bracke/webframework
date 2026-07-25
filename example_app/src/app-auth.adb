with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Calendar;
with Web.Security;

with Identity.Adapters.Repositories.Memory;
with Identity.Adapters.Repositories.Stores;
with Identity.Operations.Contexts;
with Identity.Operations.Principals.Create;
with Identity.Operations.Identities.Add;
with Identity.Operations.Passwords.Enroll;
with Identity.Operations.Passwords.Authenticate;
with Identity.Operations.Accounts.Create;
with Identity.Operations.Sessions.Create;
with Identity.Operations.Sessions.Lookup;
with Identity.Operations.Sessions.Revoke;
with Identity.Operations.Cancellation;
with Identity.Operations.Disclosure;
with Identity.Sessions.Handles;
with Identity.Assurance.Levels;
with Identity.Times;
with Identity.Times.Expirations;
with Identity.Identifiers;
with Identity.Identifiers.Entities;
with Identity.Identifiers.Operations;
with Identity.Identifiers.Registry;
with Identity.Identities.Bindings;
with Identity.Identities.Subjects;
with Identity.Principals.Definitions;
with Identity.Principals.Kinds;
with Identity.Results;
with Identity.Secrets.Passwords;
with Identity.Secrets.Text;
with Identity.Text.Bounded;
with Identity.Events.Envelopes;
with Identity.Authentication.Results;

--  Credential store backed by the identity library's in-memory repository. Each
--  user is a real identity principal with a username binding and an enrolled
--  password credential; authentication runs through Passwords.Authenticate,
--  which hashes and checks the password inside the repository. The store is
--  guarded by a protected object because a Memory.Store is not task-safe and
--  Authenticate mutates it (attempt records / lockout).
package body App.Auth is

   package Mem       renames Identity.Adapters.Repositories.Memory;
   package Stores    renames Identity.Adapters.Repositories.Stores;
   package Ctxs      renames Identity.Operations.Contexts;
   package Pr_Create renames Identity.Operations.Principals.Create;
   package Id_Add    renames Identity.Operations.Identities.Add;
   package Pw_Enroll renames Identity.Operations.Passwords.Enroll;
   package Pw_Auth   renames Identity.Operations.Passwords.Authenticate;
   package Ac_Create renames Identity.Operations.Accounts.Create;
   package Ss_Create renames Identity.Operations.Sessions.Create;
   package Ss_Lookup renames Identity.Operations.Sessions.Lookup;
   package Ss_Revoke renames Identity.Operations.Sessions.Revoke;
   package Handles   renames Identity.Sessions.Handles;
   package Levels    renames Identity.Assurance.Levels;
   package Times     renames Identity.Times;
   package Expir     renames Identity.Times.Expirations;
   package Ids       renames Identity.Identifiers;
   package Ent       renames Identity.Identifiers.Entities;
   package Op_Ids    renames Identity.Identifiers.Operations;
   package Reg_Ids   renames Identity.Identifiers.Registry;
   package Bindings  renames Identity.Identities.Bindings;
   package Subjects  renames Identity.Identities.Subjects;
   package Pr_Def    renames Identity.Principals.Definitions;
   package Pr_Kind   renames Identity.Principals.Kinds;
   package Res       renames Identity.Results;
   package Sec_Pw    renames Identity.Secrets.Passwords;
   package Sec_Txt   renames Identity.Secrets.Text;
   package Btext     renames Identity.Text.Bounded;
   package Envelopes renames Identity.Events.Envelopes;
   package Auth_Res  renames Identity.Authentication.Results;
   package Cancel    renames Identity.Operations.Cancellation;
   package Disc      renames Identity.Operations.Disclosure;

   use type Stores.Command_Status;
   use type Times.Instant;

   function U (Value : String) return Unbounded_String
     renames To_Unbounded_String;

   --  Typed id constructors from a 36-character textual id.
   function Enc (S : String) return Ids.Encoded_Identifier
     renames Ids.From_String;

   --  A system-actor operation context, reused for every store command.
   Audit_Context : constant Ctxs.Operation_Context :=
     (Operation    =>
        Op_Ids.Operation (Enc ("a0000000-0000-0000-0000-000000000001")),
      Correlation  =>
        Op_Ids.Correlation (Enc ("a0000000-0000-0000-0000-000000000002")),
      Causation    => (Present => False),
      Request      => (Present => False),
      Actor        =>
        (Kind => Envelopes.System_Principal, Principal => (Present => False)),
      Requested_At => 1,
      Deadline     => (Present => False, Time_Point => 0),
      Cancellation => (State => Cancel.Not_Cancelled),
      Disclosure   => Disc.Untrusted_Interactive,
      Diagnostic_Mode => False);

   --  The subject kind used for username bindings and lookups.
   Username_Kind : constant Reg_Ids.Registry_Id :=
     Reg_Ids.From_String ("identity.subject.username");

   --  A fresh event id per store command; the store rejects duplicates.
   Event_Counter : Natural := 0;
   function Next_Event return Ent.Event_Id is
      Suffix : String (1 .. 12) := [others => '0'];
   begin
      Event_Counter := Event_Counter + 1;
      declare
         Image : constant String :=
           Ada.Strings.Fixed.Trim (Natural'Image (Event_Counter), Ada.Strings.Left);
      begin
         Suffix (Suffix'Last - Image'Length + 1 .. Suffix'Last) := Image;
      end;
      return Ent.Event (Enc ("e0000000-0000-0000-0000-" & Suffix));
   end Next_Event;

   --  The seeded users. The identity ids are opaque; Principal is the
   --  authorization principal id the rest of the app carries.
   type Seed_User is record
      Username  : Unbounded_String;
      Password  : Unbounded_String;
      Principal : Unbounded_String;
      Clearance : Natural;           --  the user's role/clearance
      Pid       : Unbounded_String;  --  identity principal id
      Aid       : Unbounded_String;  --  identity account id
      Bid       : Unbounded_String;  --  identity binding id
      Cid       : Unbounded_String;  --  credential id
   end record;

   Seeds : constant array (1 .. 2) of Seed_User :=
     [1 => (U ("admin"),  U ("admin123"),  U ("d.principal.admin"), 100,
            U ("11111111-1111-1111-1111-111111111111"),
            U ("14444444-4444-4444-4444-444444444444"),
            U ("12222222-2222-2222-2222-222222222222"),
            U ("13333333-3333-3333-3333-333333333333")),
      2 => (U ("viewer"), U ("viewer123"), U ("d.principal.viewer"), 10,
            U ("21111111-1111-1111-1111-111111111111"),
            U ("24444444-4444-4444-4444-444444444444"),
            U ("22222222-2222-2222-2222-222222222222"),
            U ("23333333-3333-3333-3333-333333333333"))];

   type Store_Ref is access Mem.Store;

   --  Wall-clock instant (seconds), so identity session expiry is meaningful.
   function Now return Times.Instant is
      use Ada.Calendar;
   begin
      return Times.Instant (Long_Long_Integer (Clock - Time_Of (2000, 1, 1)));
   end Now;

   --  A unique UUID with the given 8-hex first group and a counter suffix.
   Session_Counter : Natural := 0;
   function Session_Uuid (Group : String; N : Natural) return String is
      Suffix : String (1 .. 12) := [others => '0'];
      Image  : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left);
   begin
      Suffix (Suffix'Last - Image'Length + 1 .. Suffix'Last) := Image;
      return Group & "-0000-0000-0000-" & Suffix;
   end Session_Uuid;

   --  Map between the app's authorization principal ids and the identity ones.
   function Identity_Pid_Of (Principal : String) return String is
   begin
      for S of Seeds loop
         if To_String (S.Principal) = Principal then
            return To_String (S.Pid);
         end if;
      end loop;
      return "";
   end Identity_Pid_Of;

   function Authz_Of_Pid (Pid_Text : String) return String is
   begin
      for S of Seeds loop
         if To_String (S.Pid) = Pid_Text then
            return To_String (S.Principal);
         end if;
      end loop;
      return "";
   end Authz_Of_Pid;

   --  All repository access is serialized where it mutates: a Memory.Store is
   --  not task-safe. Validate_Session is a protected function (read-only lookup)
   --  so concurrent requests can validate their sessions in parallel.
   protected Vault is
      procedure Setup;
      procedure Authenticate
        (Username  : String;
         Password  : String;
         Principal : out Unbounded_String);
      procedure Create_Session
        (Principal : String;
         Reference : String;
         Secret    : String;
         Success   : out Boolean);
      function Validate_Session
        (Reference : String; Secret : String) return Unbounded_String;
      function Session_Assurance
        (Reference : String; Secret : String) return Unbounded_String;
      procedure Revoke_Session (Reference : String; Secret : String);
   private
      Store : Store_Ref := null;
      Ready : Boolean := False;
   end Vault;

   protected body Vault is

      procedure Setup is
      begin
         if Ready then
            return;
         end if;

         Store := new Mem.Store;
         Mem.Initialize (Store.all);

         for S of Seeds loop
            declare
               Pid     : constant Ent.Principal_Id :=
                 Ent.Principal (Enc (To_String (S.Pid)));
               Subject : constant Btext.Bounded_Text :=
                 Btext.From_String (To_String (S.Username));
               Secret  : constant Sec_Pw.New_Password :=
                 Sec_Txt.From_UTF_8 (To_String (S.Password));
               Cmd     : Stores.Command_Status;
            begin
               Cmd := Pr_Create.Execute
                 (Store.all,
                  (Id => Pid, Kind => Pr_Kind.Human,
                   State => Pr_Def.Active, Version => 0),
                  Audit_Context, Next_Event, 1);
               if Cmd /= Stores.Applied then
                  raise Program_Error with "identity: principal create failed";
               end if;

               --  The account holds the authentication state (attempts, lock);
               --  Authenticate updates it, so it must exist.
               Cmd := Ac_Create.Execute
                 (Store.all,
                  (Id => Ent.Account (Enc (To_String (S.Aid))),
                   Principal => Pid, State => (others => <>), Version => 0),
                  Audit_Context, Next_Event, 1);
               if Cmd /= Stores.Applied then
                  raise Program_Error with "identity: account create failed";
               end if;

               Cmd := Id_Add.Execute
                 (Store.all,
                  (Id => Ent.Identity_Binding (Enc (To_String (S.Bid))),
                   Principal => Pid, Kind => Username_Kind,
                   Normalized => Subject, State => Bindings.Active, Version => 0),
                  Audit_Context, Next_Event, 1);
               if Cmd /= Stores.Applied then
                  raise Program_Error with "identity: binding add failed";
               end if;

               Cmd := Pw_Enroll.Execute
                 (Store.all, Pid, Ent.Credential (Enc (To_String (S.Cid))), Secret,
                  Audit_Context, Next_Event, 1);
               if Cmd /= Stores.Applied then
                  raise Program_Error with "identity: password enroll failed";
               end if;
            end;
         end loop;

         Ready := True;
      end Setup;

      procedure Authenticate
        (Username  : String;
         Password  : String;
         Principal : out Unbounded_String)
      is
         Subject   : constant Subjects.Authentication_Subject :=
           (Kind => Username_Kind, Value => Btext.From_String (Username));
         Presented : constant Sec_Pw.Presented_Password :=
           Sec_Txt.From_UTF_8 (Password);
         Result    : constant Auth_Res.Password_Authentication_Result :=
           Pw_Auth.Execute
             (Store.all, Subject, Presented, Audit_Context, Next_Event, 2);
      begin
         Principal := Null_Unbounded_String;
         if Res.Successful (Result.Status) then
            --  Map the authenticated username to its authorization principal.
            for S of Seeds loop
               if To_String (S.Username) = Username then
                  Principal := S.Principal;
                  return;
               end if;
            end loop;
         end if;
      end Authenticate;

      procedure Create_Session
        (Principal : String;
         Reference : String;
         Secret    : String;
         Success   : out Boolean)
      is
         Pid_Text : constant String := Identity_Pid_Of (Principal);
      begin
         Success := False;
         if Store = null or else Pid_Text = "" then
            return;
         end if;

         Session_Counter := Session_Counter + 1;
         declare
            T   : constant Times.Instant := Now;
            Cmd : constant Stores.Command_Status :=
              Ss_Create.Execute
                (Store.all,
                 Ss_Create.Create_Request'
                   (Id => Ent.Session
                            (Enc (Session_Uuid ("50000000", Session_Counter))),
                  Family => Ent.Session_Family
                              (Enc (Session_Uuid ("f0000000", Session_Counter))),
                  Principal => Ent.Principal (Enc (Pid_Text)),
                  Credential => (Present => False),
                  External_Provider => (Present => False),
                  Public_Reference => Btext.From_String (Reference),
                  Secret => Sec_Txt.From_UTF_8 (Secret),
                  --  A password login is an interactive credential
                  --  presentation, so the session is Interactive assurance --
                  --  the level the manage policy demands as a step-up.
                  Assurance => Levels.Interactive,
                  Attributes => (Recent_Authentication => True, others => <>),
                  Created_At => T,
                  Original_Authenticated_At => T,
                  Primary_Authenticated_At => T,
                  MFA_Completed_At => (Present => False),
                  Step_Up_At => (Present => False),
                  Last_Seen_At => T,
                  Idle_Expires_At => Expir.At_Time (T + 3_600),
                  Absolute_Expires_At => Expir.At_Time (T + 86_400),
                  Remembered => False,
                  Generation => 0),
                 Audit_Context, Next_Event, T);
         begin
            Success := Cmd = Stores.Applied;
         end;
      end Create_Session;

      function Validate_Session
        (Reference : String; Secret : String) return Unbounded_String is
      begin
         if Store = null then
            return Null_Unbounded_String;
         end if;

         declare
            Handle : constant Handles.Session_Handle :=
              Ss_Lookup.Execute
                (Store.all, Btext.From_String (Reference),
                 Sec_Txt.From_UTF_8 (Secret), Now);
         begin
            if Handles.Found (Handle.Status) then
               return To_Unbounded_String
                 (Authz_Of_Pid (Ent.To_String (Handle.Principal)));
            end if;
            return Null_Unbounded_String;
         end;
      end Validate_Session;

      --  The live session's assurance level, straight from the identity handle.
      --  A production impl would return the principal and assurance in the one
      --  lookup Validate_Session already does; kept separate here so the public
      --  Validate_Session signature stays a simple principal query.
      function Session_Assurance
        (Reference : String; Secret : String) return Unbounded_String is
      begin
         if Store = null then
            return Null_Unbounded_String;
         end if;

         declare
            Handle : constant Handles.Session_Handle :=
              Ss_Lookup.Execute
                (Store.all, Btext.From_String (Reference),
                 Sec_Txt.From_UTF_8 (Secret), Now);
         begin
            if Handles.Found (Handle.Status) then
               return To_Unbounded_String
                 (Levels.Assurance_Level'Image (Handle.Assurance));
            end if;
            return Null_Unbounded_String;
         end;
      end Session_Assurance;

      procedure Revoke_Session (Reference : String; Secret : String) is
      begin
         if Store = null then
            return;
         end if;

         declare
            Handle : constant Handles.Session_Handle :=
              Ss_Lookup.Execute
                (Store.all, Btext.From_String (Reference),
                 Sec_Txt.From_UTF_8 (Secret), Now);
         begin
            if Handles.Found (Handle.Status) then
               declare
                  Cmd : constant Stores.Command_Status :=
                    Ss_Revoke.Execute
                      (Store.all, Handle.Session, Audit_Context, Next_Event, Now);
               begin
                  null;  --  best-effort revoke; result intentionally ignored
               end;
            end if;
         end;
      end Revoke_Session;

   end Vault;

   function Clearance_Of (Principal : String) return Natural is
   begin
      for S of Seeds loop
         if To_String (S.Principal) = Principal then
            return S.Clearance;
         end if;
      end loop;
      return 0;
   end Clearance_Of;

   procedure Initialize is
   begin
      Vault.Setup;
   end Initialize;

   function Authenticate (Username : String; Password : String) return String is
      Principal : Unbounded_String;
   begin
      Vault.Authenticate (Username, Password, Principal);
      return To_String (Principal);
   end Authenticate;

   function Create_Session (Principal : String) return String is
      Reference : constant String := Web.Security.New_Session_Id;
      Secret    : constant String := Web.Security.New_Session_Id;
      Success   : Boolean;
   begin
      Vault.Create_Session (Principal, Reference, Secret, Success);
      if Success then
         return Reference & "|" & Secret;
      else
         return "";
      end if;
   end Create_Session;

   function Validate_Session (Token : String) return String is
      Bar : constant Natural := Ada.Strings.Fixed.Index (Token, "|");
   begin
      if Bar = 0 then
         return "";
      end if;
      return To_String
        (Vault.Validate_Session
           (Token (Token'First .. Bar - 1), Token (Bar + 1 .. Token'Last)));
   end Validate_Session;

   function Session_Assurance (Token : String) return String is
      Bar : constant Natural := Ada.Strings.Fixed.Index (Token, "|");
   begin
      if Bar = 0 then
         return "";
      end if;
      return To_String
        (Vault.Session_Assurance
           (Token (Token'First .. Bar - 1), Token (Bar + 1 .. Token'Last)));
   end Session_Assurance;

   procedure Revoke_Session (Token : String) is
      Bar : constant Natural := Ada.Strings.Fixed.Index (Token, "|");
   begin
      if Bar = 0 then
         return;
      end if;
      Vault.Revoke_Session
        (Token (Token'First .. Bar - 1), Token (Bar + 1 .. Token'Last));
   end Revoke_Session;

end App.Auth;

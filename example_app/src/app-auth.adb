with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Identity.Adapters.Repositories.Memory;
with Identity.Adapters.Repositories.Stores;
with Identity.Operations.Contexts;
with Identity.Operations.Principals.Create;
with Identity.Operations.Identities.Add;
with Identity.Operations.Passwords.Enroll;
with Identity.Operations.Passwords.Authenticate;
with Identity.Operations.Accounts.Create;
with Identity.Operations.Cancellation;
with Identity.Operations.Disclosure;
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

   --  All repository access is serialized: a Memory.Store is not task-safe and
   --  Authenticate mutates it.
   protected Vault is
      procedure Setup;
      procedure Authenticate
        (Username  : String;
         Password  : String;
         Principal : out Unbounded_String);
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

end App.Auth;

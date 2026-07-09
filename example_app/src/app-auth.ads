--  Authentication types and operations for example app.
with Database;

package App.Auth is
   --  User record for authentication.
   type User_Record is record
      Id       : Natural;
      Username : String (1 .. 50);
      Password : String (1 .. 64);  --  Should be hashed in production
      Email    : String (1 .. 100);
   end record;

   --  Authentication result.
   type Auth_Result is (Success, Invalid_Credentials, User_Not_Found);

   --  Initialize authentication system (creates admin user if needed).
   --  @return No return value.
   procedure Initialize;

   --  Authenticate a user by username and password.
   --  @param Username User's username.
   --  @param Password User's password.
   --  @return Authentication result and user ID if successful.
   procedure Authenticate 
     (Username : String;
      Password : String;
      User_Id  : out Natural;
      Result   : out Auth_Result);

   --  Get user by ID from database.
   --  @param User_Id User ID.
   --  @return User record or null if not found.
   function Get_User (User_Id : Natural) return User_Record;

   --  Get user by username from database.
   --  @param Username Username.
   --  @return User record or null if not found.
   function Get_User_By_Username (Username : String) return User_Record;

   --  Check if a user exists by username.
   --  @param Username Username.
   --  @return True if user exists.
   function User_Exists (Username : String) return Boolean;

   --  Create a new user in the database.
   --  @param Username User's username.
   --  @param Password User's password.
   --  @param Email User's email.
   --  @return New user ID.
   function Create_User (Username : String; Password : String; Email : String) return Natural;
end App.Auth;

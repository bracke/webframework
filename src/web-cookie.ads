with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;

package Web.Cookie is
   package Cookie_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => String,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Cookie_Jar is record
      Values : Cookie_Maps.Map;
      Counts : Cookie_Maps.Map;
   end record;

   type Same_Site_Mode is (Strict, Lax, None);

   type Cookie_Options is record
      Path      : String (1 .. 1) := "/";
      Http_Only : Boolean := True;
      Secure    : Boolean := False;
      Same_Site : Same_Site_Mode := Lax;
      Max_Age   : Integer := -1;
   end record;

   --  Parse a Cookie request header.
   --  @param Header Cookie header value.
   --  @return Parsed cookie jar.
   function Parse (Header : String) return Cookie_Jar;

   --  Check whether a parsed cookie exists.
   --  @param Jar Parsed cookie jar.
   --  @param Name Cookie name.
   --  @return True when the cookie exists.
   function Has (Jar : Cookie_Jar; Name : String) return Boolean;

   --  Return a parsed cookie value.
   --  @param Jar Parsed cookie jar.
   --  @param Name Cookie name.
   --  @return Cookie value or an empty string.
   function Value (Jar : Cookie_Jar; Name : String) return String;

   --  Return the number of valid cookie occurrences for a name.
   --  @param Jar Parsed cookie jar.
   --  @param Name Cookie name.
   --  @return Number of valid occurrences.
   function Count (Jar : Cookie_Jar; Name : String) return Natural;

   --  Build a Set-Cookie header value.
   --  @param Name Cookie name.
   --  @param Value Cookie value.
   --  @param Options Cookie options.
   --  @return Header value without the Set-Cookie prefix.
   function Set_Cookie
     (Name    : String;
      Value   : String;
      Options : Cookie_Options) return String;

   --  Build a Set-Cookie header value with an explicit path string.
   --  @param Name Cookie name.
   --  @param Value Cookie value.
   --  @param Path Cookie path.
   --  @param Http_Only True to emit HttpOnly.
   --  @param Secure True to emit Secure.
   --  @param Same_Site SameSite cookie policy.
   --  @param Max_Age Max-Age value, or negative to omit.
   --  @return Header value without the Set-Cookie prefix.
   function Set_Cookie
     (Name      : String;
      Value     : String;
      Path      : String;
      Http_Only : Boolean := True;
      Secure    : Boolean := False;
      Same_Site : Same_Site_Mode := Lax;
      Max_Age   : Integer := -1) return String;
end Web.Cookie;

with Ada.Strings.Unbounded;
with Web.Binding.Sources;

--  Route-capture source.
--
--  This framework's router matches exact paths and produces no path captures, so
--  route parameters are supplied explicitly by the handler (from whatever it
--  matched) and looked up here. Names are unique by construction; Lookup yields
--  zero or one occurrence.
package Web.Binding.Route is

   --  The hard cap on captures.
   Max_Captures : constant := 64;

   type Route_Captures is private;

   --  An empty capture set.
   --  @return An empty set.
   function Empty return Route_Captures;

   --  A capture set with one more (name, value). Excess captures are dropped.
   --  @param Captures The set to extend.
   --  @param Name The capture name.
   --  @param Value The capture value.
   --  @return The extended set.
   function Add
     (Captures : Route_Captures;
      Name     : String;
      Value    : String) return Route_Captures;

   --  The value captured for Name, as occurrences (zero or one).
   --  @param Captures The capture set.
   --  @param Name The capture name.
   --  @return The occurrences.
   function Lookup
     (Captures : Route_Captures; Name : String)
      return Web.Binding.Sources.Occurrences;

   --  The number of captures.
   --  @param Captures The capture set.
   --  @return The count.
   function Count (Captures : Route_Captures) return Natural;

private

   type Capture is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Capture_Array is array (1 .. Max_Captures) of Capture;

   type Route_Captures is record
      Length : Natural := 0;
      Items  : Capture_Array;
   end record;

end Web.Binding.Route;

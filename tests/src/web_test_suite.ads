with AUnit.Test_Suites;

package Web_Test_Suite is
   --  Build the complete framework test suite.
   --  @return Access to the complete AUnit suite.
   function Suite return AUnit.Test_Suites.Access_Test_Suite;
end Web_Test_Suite;

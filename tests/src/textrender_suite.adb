with AUnit.Test_Cases;
with Textrender.BasicTests;

package body Textrender_Suite is

   function Suite return Access_Test_Suite is
      type Test_Case_Access is access all AUnit.Test_Cases.Test_Case'Class;
      Ret : constant Access_Test_Suite := new Test_Suite;
   begin
      Ret.Add_Test (Test_Case_Access'(new Textrender.BasicTests.Textrender_Basic_Case));

      return Ret;
   end Suite;

end Textrender_Suite;
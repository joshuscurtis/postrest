module Feature.SingularSpec where

import Text.Heredoc
import Test.Hspec
import Test.Hspec.Wai
import Test.Hspec.Wai.JSON
import Network.HTTP.Types
import Network.Wai.Test (SResponse(..))

import Network.Wai (Application)

import SpecHelper
import Protolude hiding (get)


spec :: SpecWith Application
spec =
  describe "Requesting singular json object" $ do
    let pgrstObj = "application/vnd.pgrst.object+json"
        singular = ("Accept", pgrstObj)

    context "with GET request" $ do
      it "fails for zero rows" $
        request methodGet  "/items?id=gt.0&id=lt.0" [singular] ""
          `shouldRespondWith` 406

      it "will select an existing object" $ do
        request methodGet "/items?id=eq.5" [singular] ""
          `shouldRespondWith` [str|{"id":5}|]
        -- also test without the +json suffix
        request methodGet "/items?id=eq.5"
          [("Accept", "application/vnd.pgrst.object")] ""
          `shouldRespondWith` [str|{"id":5}|]

      it "can combine multiple prefer values" $
        request methodGet "/items?id=eq.5" [singular, ("Prefer","count=none")] ""
          `shouldRespondWith` [str|{"id":5}|]

      it "can shape plurality singular object routes" $
        request methodGet "/projects_view?id=eq.1&select=id,name,clients{*},tasks{id,name}" [singular] ""
          `shouldRespondWith`
            [str|{"id":1,"name":"Windows 7","clients":{"id":1,"name":"Microsoft"},"tasks":[{"id":1,"name":"Design w7"},{"id":2,"name":"Code w7"}]}|]

    context "when updating rows" $ do

      it "works for one row" $ do
        _ <- post "/addresses" [json| { id: 97, address: "A Street" } |]
        request methodPatch
          "/addresses?id=eq.97"
          [("Prefer", "return=representation"), singular]
          [json| { address: "B Street" } |]
          `shouldRespondWith`
            [str|{"id":97,"address":"B Street"}|]

      it "raises an error for multiple rows" $ do
        _ <- post "/addresses" [json| { id: 98, address: "xxx" } |]
        _ <- post "/addresses" [json| { id: 99, address: "yyy" } |]
        p <- request methodPatch
          "/addresses?id=gt.0"
          [("Prefer", "return=representation"), singular]
          [json| { address: "zzz" } |]
        liftIO $ do
          simpleStatus p `shouldBe` notAcceptable406
          isErrorFormat (simpleBody p) `shouldBe` True

      it "raises an error for zero rows" $ do
        p <- request methodPatch  "/items?id=gt.0&id=lt.0"
          [("Prefer", "return=representation"), singular] [json|{"id":1}|]
        liftIO $ do
          simpleStatus p `shouldBe` notAcceptable406
          isErrorFormat (simpleBody p) `shouldBe` True

    context "when creating rows" $ do

      it "works for one row" $ do
        p <- request methodPost
          "/addresses"
          [("Prefer", "return=representation"), singular]
          [json| [ { id: 100, address: "xxx" } ] |]
        liftIO $ simpleBody p `shouldBe` [str|{"id":100,"address":"xxx"}|]

      it "raises an error when attempting to create multiple entities with singular object accept header" $ do
        p <- request methodPost
          "/addresses"
          [("Prefer", "return=representation"), singular]
          [json| [ { id: 100, address: "xxx" }, { id: 101, address: "xxx" } ] |]
        liftIO $ simpleStatus p `shouldBe` notAcceptable406

      it "raises an error when creating zero entities with vnd.pgrst.object" $ do
        p <- request methodPost
          "/addresses"
          [("Prefer", "return=representation"), singular]
          [json| [ ] |]
        liftIO $ do
          simpleStatus p `shouldBe` notAcceptable406
          isErrorFormat (simpleBody p) `shouldBe` True

    context "when calling a stored proc" $ do

      it "fails for zero rows" $ do
        p <- request methodPost "/rpc/getproject"
          [singular] [json|{ "id": 9999999}|]
        liftIO $ do
          simpleStatus p `shouldBe` notAcceptable406
          isErrorFormat (simpleBody p) `shouldBe` True

      -- this one may be controversial, should vnd.pgrst.object include
      -- the likes of 2 and "hello?"
      it "succeeds for scalar result" $
        request methodPost "/rpc/sayhello"
          [singular] [json|{ "name": "world"}|]
          `shouldRespondWith` 200

      it "returns a single object for json proc" $
        request methodPost "/rpc/getproject"
          [singular] [json|{ "id": 1}|] `shouldRespondWith`
          [str|{"id":1,"name":"Windows 7","client_id":1}|]

      it "fails for multiple rows" $ do
        p <- request methodPost "/rpc/getallprojects" [singular] "{}"
        liftIO $ do
          simpleStatus p `shouldBe` notAcceptable406
          isErrorFormat (simpleBody p) `shouldBe` True
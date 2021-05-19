{-# LANGUAGE RecordWildCards #-}

module Smos.Server.Handler.PutUserSubscriptionSpec
  ( spec,
  )
where

import Smos.Client
import Smos.Data.Gen ()
import Smos.Server.TestUtils
import Test.Syd
import Test.Syd.Validity

spec :: Spec
spec =
  describe "PutUserSubscription" $
    serverSpec $
      it "can set a subscription that GetUserSubscription can get" $ \cenv ->
        forAllValid $ \utct ->
          withAdminUser cenv $ \adminT ->
            withNewUserAndData cenv $ \Register {..} t -> do
              NoContent <- testClient cenv $ clientPutUserSubscription adminT registerUsername utct
              UserSubscription {..} <- testClient cenv $ clientGetUserSubscription t
              userSubscriptionEnd `shouldBe` Just utct

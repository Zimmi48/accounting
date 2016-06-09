module MyKinvey exposing
  ( signup
  , login
  , getUserData
  , setUserData
  , createData
  , createDataSimple
  , getData
  )


import Task
import Json.Decode
import Kinvey


auth : Kinvey.Auth
auth =
  { appId = "kid_ZkL79b5Kbb"
  , appSecret = "aa5f8ad01ed7447fbb9a65fbd8b1f901"
  }


signup = Kinvey.signup auth


login username password =
  Task.map
    (\(session, _) -> session)
    (Kinvey.login auth username password (Json.Decode.succeed ()))


getUserData = Kinvey.getUserData auth


setUserData = Kinvey.setUserData auth


createData = Kinvey.createData auth


createDataSimple = Kinvey.createDataSimple auth


getData = Kinvey.getData auth


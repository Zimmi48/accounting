

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.App as App
import Kinvey exposing (..)


main =
  App.program
     { init = init
     , update = update
     , view = view
     , subscriptions = \_ -> Sub.none
     }


auth : Auth
auth =
  { appId = "kid_ZkL79b5Kbb"
  , appSecret = "aa5f8ad01ed7447fbb9a65fbd8b1f901"
  }


type Model
  = Login LoginModel
  | LoggedIn LoggedInModel

type alias LoginModel =
  { username : String
  , password : String
  }


type alias LoggedInModel =
  { session : Maybe Session
  , transactions : List String
  }


init : (Model, Cmd msg)
init =
  ( Login (LoginModel "" "")
  , Cmd.none
  )


type Msg
  = NoOp


update : Msg -> Model -> (Model, Cmd msg)
update msg model =
  case msg of
    NoOp ->
      (model, Cmd.none)


view : Model -> Html msg
view model =
  case model of
    Login model ->
      viewLogin model

    LoggedIn model ->
      viewLoggedIn model


viewLogin : LoginModel -> Html msg
viewLogin model =
  div []
    [ input [ placeholder "Username" ] []
    , input [ type' "password" , placeholder "Password" ] []
    , button [] [ text "Login" ]
    ]


viewLoggedIn : LoggedInModel -> Html msg
viewLoggedIn model =
  div []
    [ text "Success!"
    ]




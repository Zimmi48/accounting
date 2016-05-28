port module Main exposing (..)


import Html exposing (..)
import Html.App as App
import Kinvey exposing (Session)
import Login
import LoggedIn


main : Program (Maybe Session)
main =
  App.programWithFlags
     { init = init
     , update = update
     , view = view
     , subscriptions = \_ -> Sub.none
     }


port setStorage : Session -> Cmd msg


type Model
  = LoginModel Login.Model
  | LoggedInModel LoggedIn.Model


init : Maybe Session -> (Model, Cmd Msg)
init savedSession =
  case savedSession of
    Nothing ->
      let (model, cmd) = Login.init in
      LoginModel model ! [ cmd ]

    Just session ->
      let (model, cmd) = LoggedIn.init session in
      LoggedInModel model !
        [ Cmd.map LoggedInMsg cmd
        , setStorage session -- save session token for later use
        ]


type Msg
  = NoOp
  | LoginMsg Login.Msg
  | LoggedInMsg LoggedIn.Msg


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case ( msg , model ) of
    ( LoginMsg msg , LoginModel model ) ->
      case Login.update msg model of
        Login.Update (model, cmd) ->
          ( LoginModel model , Cmd.map LoginMsg cmd )

        Login.NewSession session ->
          init (Just session)

    ( LoggedInMsg msg , LoggedInModel model ) ->
      case LoggedIn.update msg model of
        Nothing ->
          init Nothing

        Just (model, cmd) ->
          ( LoggedInModel model , Cmd.map LoggedInMsg cmd )

    _ ->
      model ! []


view : Model -> Html Msg
view model =
  case model of
    LoginModel model ->
      App.map LoginMsg <| Login.view model

    LoggedInModel model ->
      App.map LoggedInMsg <| LoggedIn.view model





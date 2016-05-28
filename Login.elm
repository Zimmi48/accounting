module Login exposing (Model, init, view, update, Msg, UpdateResponse(..))


import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Task
import Kinvey exposing (Session)
import MyKinvey exposing (..)


-- TODO : handle Enter key


type alias Model =
  { username : String
  , password : String
  }


init : (Model, Cmd msg)
init = Model "" "" ! []


view : Model -> Html Msg
view model =
  div []
    [ input
        [ onInput Username
        , placeholder "Username"
        , value model.username
        ] []
    , input
        [ onInput Password
        , type' "password"
        , placeholder "Password"
        , value model.password
        ] []
    , button [ onClick Login ] [ text "Login" ]
    ]


type Msg
  = Username String
  | Password String
  | Login
  | Error Kinvey.Error
  | Success Session


type UpdateResponse
  = Update (Model, Cmd Msg)
  | NewSession Session


update : Msg -> Model -> UpdateResponse
update msg model =
  case msg of
    Username s ->
      Update ( { model | username = s } , Cmd.none)

    Password s ->
      Update ( { model | password = s } , Cmd.none )

    Login ->
      Update
        ( model
        , Task.perform Error Success
            <| login model.username model.password
        )

    Error _ ->
      Update init

    Success session ->
      NewSession session

module AddButton exposing (Model, init, view, Msg, update)


import Dialog
import Html exposing (..)
import Html.App as App
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode exposing (Decoder)
import Json.Encode exposing (Value)
import Kinvey exposing (Session)
import Maybe.Extra as Maybe
import MyKinvey exposing (..)
import Task


type alias Model model msg object =
  { componentModel : Maybe model
  , session : Session
  , table : String
  , decoder : Decoder object
  , title : String
  , objects : Maybe (List object)
  , componentInit : model
  , componentUpdate : msg -> model -> (model, Maybe Value)
  , componentView : model -> Html msg
  }


init
    : { session : Session
      , table : String
      , decoder : Decoder object
      , title : String
      , init : model
      , update : msg -> model -> (model, Maybe Value)
      , view : model -> Html msg
      }
    -> ( Model model msg object , Cmd (Msg msg object) )
init { session, table, decoder, title, init, update, view } =
  ( { componentModel = Nothing
    , session = session
    , table = table
    , decoder = decoder
    , title = title
    , objects = Nothing
    , componentInit = init
    , componentUpdate = update
    , componentView = view
    }
  , Task.perform Error Fetch
    <| getData session table Kinvey.NoSort decoder
  )


view : Model model msg object -> Html (Msg msg object)
view model =
  let notready = Maybe.isNothing model.objects in
  div
    [ style [ ("display", "inline-block") ] ]
    [ button
        ( [ classList
              [ ("btn", True)
              , ("btn-success", True)
              ]
          ] ++
            if notready then
              [ disabled notready ]
            else
              [ onClick Open ]
        )
        [ text model.title ]
    , Maybe.map
      (\m ->
         { closeMessage = Just Close
         , header = Just (h4 [] [text model.title])
         , body = Just (App.map ComponentMsg <| model.componentView m)
         , footer = Nothing
         }
      )
      model.componentModel
      |> Dialog.view
    ]


type Msg msg object
  = Open
  | Close
  | ComponentMsg msg
  | Created object
  | Fetch (List object)
  | Error Kinvey.Error


update
  : Msg msg object
  -> Model model msg object
  -> ( Model model msg object
     , Cmd (Msg msg object)
     , Maybe (Result Kinvey.Error (List object))
     )
update msg model =
  case msg of
    Open ->
      ( { model | componentModel = Just model.componentInit }
      , Cmd.none
      , Nothing
      )

    Close ->
      ( { model | componentModel = Nothing }
      , Cmd.none
      , Nothing
      )

    Created object ->
      let objects = Maybe.map ((::) object) model.objects in
      ( { model |
          objects = objects
        , componentModel = Nothing
        }
      , Cmd.none
      , Maybe.map Ok objects
      )

    Fetch objects ->
      ( { model | objects = Just objects }
      , Cmd.none
      , Just (Ok objects)
      )
      
    Error e ->
      ( model
      , Cmd.none
      , Just (Err e)
      )

    ComponentMsg msg ->
      case (Maybe.map (model.componentUpdate msg) model.componentModel) of
        Just (componentModel, Nothing) ->
          ( { model | componentModel = Just componentModel }
          , Cmd.none
          , Nothing
          )

        Just (componentModel, Just result) ->
          ( { model | componentModel = Just componentModel }
          , Task.perform Error Created
            <| createData model.session model.table model.decoder result
          , Nothing
          )

        Nothing ->
          ( model
          , Cmd.none
          , Nothing
          )


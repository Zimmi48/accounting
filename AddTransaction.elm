module AddTransaction exposing (Model, init, Msg, update, view)


import Date exposing (Date)
import Date.Format as Date
import DatePicker exposing (DatePicker, defaultSettings)
import Html exposing (..)
import Html.App as App
import Html.Attributes exposing (..)
import Json.Encode as Json
import Lib exposing (..)
import List.Extra as List
import Maybe
import Maybe.Extra as Maybe
import Positive exposing (Positive)
import String


main : Program Never
main =
  App.program
    { init = init True [] []
    , update =
        (\msg model ->
           let (model, cmd, _) = update msg model in
           (model, cmd)
        )
    , view = view
    , subscriptions = (\_ -> Sub.none)
    }


type alias Model =
  { object : String
  , value : Maybe (Positive Float)
  , valueString : String
  , datePicker : DatePicker
  , date : Maybe Date
  , account : Maybe Account
  , accounts : List Account
  , for : List Contact
  , contacts : List Contact
  , income : Bool
  }


init : Bool -> List Account -> List Contact -> (Model, Cmd Msg)
init income accounts contacts =
  let
    (dateModel, dateCmd) =
      DatePicker.init
        { defaultSettings |
          placeholder = "1 Jan 1970"
        , dateFormatter = Date.format "%e %b %Y"
        , firstDayOfWeek = Date.Mon
        , inputClassList = [ ("form-control", True) ]
        , inputName = Just "date"
        }

  in
    { object = ""
    , value = Nothing
    , valueString = ""
    , datePicker = dateModel
    , date = Nothing
    , account = List.head accounts
    , accounts = accounts
    , for = []
    , contacts = contacts
    , income = income
    }
  ! [ Cmd.map UpdateDate dateCmd
    ]


type Msg
  = UpdateObject String
  | UpdateValue String
  | UpdateDate DatePicker.Msg
  | UpdateAccount String
  | UpdateShare String String
  | AddContact String
  | Submit


update : Msg -> Model -> (Model, Cmd Msg, Maybe Json.Value)
update msg model =
  case msg of
    UpdateObject string ->
      ( { model |
          object = String.left 50 string
        }
      , Cmd.none
      , Nothing
      )

    UpdateValue string ->
      ( { model |
          value =
            (String.toFloat string |> Result.toMaybe)
            `Maybe.andThen` Positive.fromNum
        , valueString = string
        }
      , Cmd.none
      , Nothing
      )

    UpdateDate msg ->
      let
        (dateModel, dateCmd, date) =
          DatePicker.update msg model.datePicker
      in
      ( { model |
          datePicker = dateModel
        , date = Maybe.oneOf [date, model.date]
        }
      , Cmd.map UpdateDate dateCmd
      , Nothing
      )

    UpdateAccount id ->
      ( { model |
          account = List.find (.id >> ((==) id)) model.accounts
        }
      , Cmd.none
      , Nothing
      )

    UpdateShare _ _ ->
      (model, Cmd.none, Nothing)

    AddContact id ->
      let (newContacts, remains) = List.partition (.id >> ((==) id)) model.contacts in
      ( { model |
          for = model.for ++ newContacts
        , contacts = remains
        }
      , Cmd.none
      , Nothing
      )      

    Submit ->
      case (model.value , model.date, model.account) of
        (Just value, Just date, Just account) ->
          if String.isEmpty model.object then
            (model, Cmd.none, Nothing)

          else
            ( model
            , Cmd.none
            ,   Json.object
                  [ ("object", Json.string model.object)
                  , ( "value"
                    , Json.float
                      <| (if model.income then identity else (-) 0)
                      <| Positive.toNum value
                    )
                  , ("date", Json.string <| Date.formatISO8601 date)
                  , ("account", Json.string account.id)
                  ] |> Just
            )

        _ ->
          (model, Cmd.none, Nothing)


view : Model -> Html Msg
view model =
  viewForm
    ( String.isEmpty model.object
    || Maybe.isNothing model.value
    || Maybe.isNothing model.date
    || Maybe.isNothing model.account
    )
    Submit
    (if model.income then "Add income" else "Add expense")
    [ inputGr "object" "Object" UpdateObject
        [ placeholder "Groceries"
        , value model.object
        , required True
        ]
    , inputGr "value" "Value" UpdateValue
        [ placeholder "23.33"
        , value model.valueString
        , type' "number"
        , Html.Attributes.min "0.01"
        , step "0.01"
        , required True
        ]
    , div
        [ class "form-group" ]
        [ label [ for "date" ] [ text "Date" ]
        , App.map UpdateDate <| DatePicker.view model.datePicker
        ]
    , div []
        ( if List.isEmpty model.contacts && List.isEmpty model.for then
            []
          else
            [ selector
                "contact"
                "Share with"
                ({ name = "", email = "", id = ""} :: model.contacts)
                AddContact
                []
                False
            , List.map
                (\contact ->
                   inputGr
                     ("share-" ++ contact.id)
                     contact.name
                     (UpdateShare contact.id)
                     [ placeholder "What is their share?"
                     , type' "number"
                     , Html.Attributes.min "0"
                     , step "0.01"
                     ]
                )
                model.for
              |> div [ class "form-inline" ]
            ]
        )
    , selector "account" "Account" model.accounts UpdateAccount [] True
    ]





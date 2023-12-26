module Frontend exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Dialog
import Dict
import Dict.Extra as Dict
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Input as Input
import Html
import Html.Attributes as Attr
import Html.Events exposing (..)
import Lamdera
import List.Extra as List
import Maybe.Extra as Maybe
import String
import Tuple exposing (..)
import Types exposing (..)
import Url


type alias Model =
    FrontendModel


app =
    Lamdera.frontend
        { init = init
        , onUrlRequest = UrlClicked
        , onUrlChange = UrlChanged
        , update = update
        , updateFromBackend = updateFromBackend
        , subscriptions = \m -> Sub.none
        , view = view
        }


init : Url.Url -> Nav.Key -> ( Model, Cmd FrontendMsg )
init url key =
    ( { showDialog = Nothing
      , key = key
      }
    , Cmd.none
    )


update : FrontendMsg -> Model -> ( Model, Cmd FrontendMsg )
update msg model =
    case msg of
        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            ( model, Cmd.none )

        NoOpFrontendMsg ->
            ( model, Cmd.none )

        ShowDialog dialog ->
            ( { model | showDialog = Just dialog }
            , Cmd.none
            )

        Submit ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    ( { model | showDialog = Just (AddPersonDialog { dialogModel | submitted = True }) }
                    , Lamdera.sendToBackend (AddPerson dialogModel.name)
                    )

                Just (AddAccountOrGroupDialog dialogModel) ->
                    let
                        ownersOrMembers =
                            dialogModel.ownersOrMembers
                                |> List.map
                                    (\( ownerOrMember, share ) ->
                                        ( ownerOrMember
                                        , share
                                            |> String.toInt
                                            |> Maybe.withDefault 0
                                        )
                                    )
                                |> Dict.fromListDedupe (+)
                                |> Dict.map (\_ -> Share)
                    in
                    ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | submitted = True }) }
                    , if dialogModel.account then
                        Lamdera.sendToBackend (AddAccount dialogModel.name ownersOrMembers)

                      else
                        Lamdera.sendToBackend (AddGroup dialogModel.name ownersOrMembers)
                    )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | submitted = True }) }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        Cancel ->
            ( { model | showDialog = Nothing }
            , Cmd.none
            )

        UpdateName name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    ( { model | showDialog = Just (AddPersonDialog { dialogModel | name = name }) }
                    , Cmd.none
                    )

                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | name = name }) }
                    , Cmd.none
                    )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | description = name }) }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        UpdateOwnerOrMember index ownerOrMember share ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            if index == List.length dialogModel.ownersOrMembers then
                                                dialogModel.ownersOrMembers ++ [ ( ownerOrMember, share ) ]

                                            else
                                                List.setAt index ( ownerOrMember, share ) dialogModel.ownersOrMembers
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )

        OperationSuccessful ->
            ( { model | showDialog = Nothing }
            , Cmd.none
            )


view : Model -> Browser.Document FrontendMsg
view model =
    let
        config title inputs canSubmit =
            { closeMessage = Just Cancel
            , maskAttributes = []
            , containerAttributes =
                [ Background.color (rgb 1 1 1)
                , Border.solid
                , Border.rounded 5
                , Border.width 1
                , centerX
                , centerY
                ]
            , headerAttributes =
                [ padding 20
                , Background.color green
                ]
            , bodyAttributes = [ padding 20 ]
            , footerAttributes =
                [ Border.widthEach { top = 1, bottom = 0, left = 0, right = 0 }
                , Border.solid
                ]
            , header = Just (text title)
            , body =
                Just
                    (column [ spacing 20 ]
                        inputs
                    )
            , footer =
                Just
                    (row [ centerX, spacing 20, padding 20, alignRight ]
                        [ Input.button redButtonStyle
                            { label = text "Cancel"
                            , onPress = Just Cancel
                            }
                        , Input.button
                            (if canSubmit then
                                greenButtonStyle

                             else
                                grayButtonStyle
                            )
                            { label = text "Submit"
                            , onPress =
                                if canSubmit then
                                    Just Submit

                                else
                                    Nothing
                            }
                        ]
                    )
            }

        dialogConfig =
            model.showDialog
                |> Maybe.map
                    (\dialog ->
                        case dialog of
                            AddPersonDialog dialogModel ->
                                config "Add Person"
                                    (addPersonInputs dialogModel)
                                    (String.length dialogModel.name
                                        > 0
                                        && not dialogModel.submitted
                                    )

                            AddAccountOrGroupDialog dialogModel ->
                                let
                                    label =
                                        if dialogModel.account then
                                            "Add Account"

                                        else
                                            "Add Group"
                                in
                                config label
                                    (addAccountOrGroupInputs dialogModel)
                                    (String.length dialogModel.name
                                        > 0
                                        && (dialogModel.ownersOrMembers
                                                |> List.map second
                                                |> Maybe.traverse String.toInt
                                                |> Maybe.map (List.sum >> (\sum -> sum > 0))
                                                |> Maybe.withDefault False
                                           )
                                        && not dialogModel.submitted
                                    )

                            AddSpendingDialog dialogModel ->
                                config "Add Spending" [] False
                    )
    in
    { title = "Accounting"
    , body =
        -- Elm UI body
        [ layout
            [ inFront (Dialog.view dialogConfig)
            ]
            (column [ width fill ]
                [ row [ centerX, spacing 70, padding 20 ]
                    [ Input.button greenButtonStyle
                        { label = text "Add Person"
                        , onPress =
                            Just
                                (ShowDialog
                                    (AddPersonDialog
                                        { name = ""
                                        , submitted = False
                                        }
                                    )
                                )
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Account"
                        , onPress =
                            Just
                                (ShowDialog
                                    (AddAccountOrGroupDialog
                                        { name = ""
                                        , ownersOrMembers = []
                                        , submitted = False
                                        , account = True
                                        }
                                    )
                                )
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Group"
                        , onPress =
                            Just
                                (ShowDialog
                                    (AddAccountOrGroupDialog
                                        { name = ""
                                        , ownersOrMembers = []
                                        , submitted = False
                                        , account = False
                                        }
                                    )
                                )
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Spending"
                        , onPress =
                            Just
                                (ShowDialog
                                    (AddSpendingDialog
                                        { description = ""
                                        , day = 1
                                        , month = 1
                                        , year = 1970
                                        , totalSpending = 0
                                        , sharedSpending = []
                                        , personalSpending = []
                                        , transactions = []
                                        , submitted = False
                                        }
                                    )
                                )
                        }
                    ]
                ]
            )
        ]
    }


buttonStyle =
    [ spaceEvenly
    , padding 10
    , Border.solid
    , Border.rounded 5
    , Border.width 1
    ]


greenButtonStyle =
    buttonStyle ++ [ Background.color green ]


green =
    rgb255 152 251 152


redButtonStyle =
    buttonStyle ++ [ Background.color (rgb 1 0.5 0.5) ]


grayButtonStyle =
    buttonStyle ++ [ Background.color (rgb 0.8 0.8 0.8) ]


addPersonInputs { name } =
    [ Input.text []
        { label = Input.labelLeft [] (text "Name")
        , placeholder = Nothing
        , onChange = UpdateName
        , text = name
        }
    ]


addAccountOrGroupInputs { name, ownersOrMembers, account } =
    let
        label =
            if account then
                "Owner "

            else
                "Member "
    in
    [ Input.text []
        { label = Input.labelLeft [] (text "Name")
        , placeholder = Nothing
        , onChange = UpdateName
        , text = name
        }
    ]
        ++ List.indexedMap
            (\index ( ownerOrMember, share ) ->
                row [ spacing 20 ]
                    [ Input.text []
                        { label = Input.labelLeft [] (label ++ (index + 1 |> String.fromInt) |> text)
                        , placeholder = Nothing
                        , onChange = flip (UpdateOwnerOrMember index) share
                        , text = ownerOrMember
                        }
                    , Input.text []
                        { label = Input.labelLeft [] (text "Share")
                        , placeholder = Nothing
                        , onChange = UpdateOwnerOrMember index ownerOrMember
                        , text = share
                        }
                    ]
            )
            ownersOrMembers
        ++ (if List.all (\( ownerOrMember, _ ) -> String.length ownerOrMember > 0) ownersOrMembers then
                [ row [ spacing 20 ]
                    [ Input.text []
                        { label = Input.labelLeft [] (label ++ (List.length ownersOrMembers + 1 |> String.fromInt) |> text)
                        , placeholder = Nothing
                        , onChange = flip (UpdateOwnerOrMember (List.length ownersOrMembers)) "1"
                        , text = ""
                        }
                    , Input.text []
                        { label = Input.labelLeft [] (text "Share")
                        , placeholder = Nothing
                        , onChange = UpdateOwnerOrMember (List.length ownersOrMembers) ""
                        , text = ""
                        }
                    ]
                ]

            else
                []
           )

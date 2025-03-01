import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/network_monitor.dart';
import 'package:appflowy/env/env.dart';
import 'package:appflowy/plugins/database_view/application/field/field_action_sheet_bloc.dart';
import 'package:appflowy/plugins/database_view/application/field/field_controller.dart';
import 'package:appflowy/plugins/database_view/application/field/field_service.dart';
import 'package:appflowy/plugins/database_view/application/setting/property_bloc.dart';
import 'package:appflowy/plugins/database_view/grid/application/grid_header_bloc.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/openai/service/openai_client.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/stability_ai/stability_ai_client.dart';
import 'package:appflowy/plugins/trash/application/prelude.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/af_cloud_auth_service.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/auth/supabase_auth_service.dart';
import 'package:appflowy/user/application/auth/supabase_mock_auth_service.dart';
import 'package:appflowy/user/application/prelude.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/workspace/application/edit_panel/edit_panel_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/local_notifications/notification_action_bloc.dart';
import 'package:appflowy/workspace/application/settings/notifications/notification_settings_cubit.dart';
import 'package:appflowy/workspace/application/settings/prelude.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/user/prelude.dart';
import 'package:appflowy/workspace/application/view/prelude.dart';
import 'package:appflowy/workspace/application/workspace/prelude.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder2/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flowy_infra/file_picker/file_picker_impl.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

class DependencyResolver {
  static Future<void> resolve(
    GetIt getIt,
    IntegrationMode mode,
  ) async {
    _resolveUserDeps(getIt, mode);
    _resolveHomeDeps(getIt);
    _resolveFolderDeps(getIt);
    _resolveDocDeps(getIt);
    _resolveGridDeps(getIt);
    _resolveCommonService(getIt, mode);
  }
}

void _resolveCommonService(
  GetIt getIt,
  IntegrationMode mode,
) async {
  // getIt.registerFactory<KeyValueStorage>(() => RustKeyValue());
  getIt.registerFactory<KeyValueStorage>(() => DartKeyValue());
  getIt.registerFactory<FilePickerService>(() => FilePicker());
  if (mode.isTest) {
    getIt.registerFactory<ApplicationDataStorage>(
      () => MockApplicationDataStorage(),
    );
  } else {
    getIt.registerFactory<ApplicationDataStorage>(
      () => ApplicationDataStorage(),
    );
  }

  getIt.registerFactoryAsync<OpenAIRepository>(
    () async {
      final result = await UserBackendService.getCurrentUserProfile();
      return result.fold(
        (l) {
          throw Exception('Failed to get user profile: ${l.msg}');
        },
        (r) {
          return HttpOpenAIRepository(
            client: http.Client(),
            apiKey: r.openaiKey,
          );
        },
      );
    },
  );

  getIt.registerFactoryAsync<StabilityAIRepository>(
    () async {
      final result = await UserBackendService.getCurrentUserProfile();
      return result.fold(
        (l) {
          throw Exception('Failed to get user profile: ${l.msg}');
        },
        (r) {
          return HttpStabilityAIRepository(
            client: http.Client(),
            apiKey: r.stabilityAiKey,
          );
        },
      );
    },
  );

  getIt.registerFactory<ClipboardService>(
    () => ClipboardService(),
  );
}

void _resolveUserDeps(GetIt getIt, IntegrationMode mode) {
  switch (currentCloudType()) {
    case CloudType.unknown:
      getIt.registerFactory<AuthService>(
        () => BackendAuthService(
          AuthTypePB.Local,
        ),
      );
      break;
    case CloudType.supabase:
      if (mode.isIntegrationTest) {
        getIt.registerFactory<AuthService>(() => MockAuthService());
      } else {
        getIt.registerFactory<AuthService>(() => SupabaseAuthService());
      }
      break;
    case CloudType.appflowyCloud:
      getIt.registerFactory<AuthService>(() => AFCloudAuthService());
      break;
  }

  getIt.registerFactory<AuthRouter>(() => AuthRouter());

  getIt.registerFactory<SignInBloc>(
    () => SignInBloc(getIt<AuthService>()),
  );
  getIt.registerFactory<SignUpBloc>(
    () => SignUpBloc(getIt<AuthService>()),
  );

  getIt.registerFactory<SplashRouter>(() => SplashRouter());
  getIt.registerFactory<EditPanelBloc>(() => EditPanelBloc());
  getIt.registerFactory<SplashBloc>(() => SplashBloc());
  getIt.registerLazySingleton<NetworkListener>(() => NetworkListener());
}

void _resolveHomeDeps(GetIt getIt) {
  getIt.registerSingleton(FToast());

  getIt.registerSingleton(MenuSharedState());

  getIt.registerFactoryParam<UserListener, UserProfilePB, void>(
    (user, _) => UserListener(userProfile: user),
  );

  getIt.registerFactoryParam<WorkspaceBloc, UserProfilePB, void>(
    (user, _) => WorkspaceBloc(
      userService: UserBackendService(userId: user.id),
    ),
  );

  // share
  getIt.registerFactoryParam<DocShareBloc, ViewPB, void>(
    (view, _) => DocShareBloc(view: view),
  );

  getIt.registerSingleton<NotificationActionBloc>(NotificationActionBloc());

  getIt.registerLazySingleton<TabsBloc>(() => TabsBloc());

  getIt.registerSingleton<NotificationSettingsCubit>(
    NotificationSettingsCubit(),
  );

  getIt.registerSingleton<ReminderBloc>(
    ReminderBloc(notificationSettings: getIt<NotificationSettingsCubit>()),
  );
}

void _resolveFolderDeps(GetIt getIt) {
  //workspace
  getIt.registerFactoryParam<WorkspaceListener, UserProfilePB, String>(
    (user, workspaceId) => WorkspaceListener(
      user: user,
      workspaceId: workspaceId,
    ),
  );

  getIt.registerFactoryParam<ViewBloc, ViewPB, void>(
    (view, _) => ViewBloc(
      view: view,
    ),
  );

  //Settings
  getIt.registerFactoryParam<SettingsDialogBloc, UserProfilePB, void>(
    (user, _) => SettingsDialogBloc(user),
  );

  //User
  getIt.registerFactoryParam<SettingsUserViewBloc, UserProfilePB, void>(
    (user, _) => SettingsUserViewBloc(user),
  );

  // trash
  getIt.registerLazySingleton<TrashService>(() => TrashService());
  getIt.registerLazySingleton<TrashListener>(() => TrashListener());
  getIt.registerFactory<TrashBloc>(
    () => TrashBloc(),
  );
  getIt.registerFactory<FavoriteBloc>(() => FavoriteBloc());
}

void _resolveDocDeps(GetIt getIt) {
// Doc
  getIt.registerFactoryParam<DocumentBloc, ViewPB, void>(
    (view, _) => DocumentBloc(view: view),
  );
}

void _resolveGridDeps(GetIt getIt) {
  getIt.registerFactoryParam<GridHeaderBloc, String, FieldController>(
    (viewId, fieldController) => GridHeaderBloc(
      viewId: viewId,
      fieldController: fieldController,
    ),
  );

  getIt.registerFactoryParam<FieldActionSheetBloc, FieldContext, void>(
    (data, _) => FieldActionSheetBloc(fieldCellContext: data),
  );

  getIt.registerFactoryParam<DatabasePropertyBloc, String, FieldController>(
    (viewId, cache) =>
        DatabasePropertyBloc(viewId: viewId, fieldController: cache),
  );
}

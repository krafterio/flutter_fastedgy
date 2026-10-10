/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// The lists of an application, without their interface, as vue-fastedgy
/// gives them: the data iterator, its table and its grid, the page size, the
/// selection, the manual order, the quick filters, the state in the URL, the
/// column filters, the custom views, the neighbours of a record in its list,
/// the options of a relation. No Material and no Cupertino: an application imports it
/// beside its usual entry point.
library;

export 'src/list/api_options.dart';
export 'src/list/column_filter.dart';
export 'src/list/column_layout.dart';
export 'src/list/custom_views.dart';
export 'src/list/data_groups.dart';
export 'src/list/data_iterator.dart';
export 'src/list/data_table.dart';
export 'src/list/list_activity.dart';
export 'src/list/list_url.dart';
export 'src/list/page_size.dart';
export 'src/list/quick_filter.dart';
export 'src/list/record_context.dart';
export 'src/list/record_edit.dart';
export 'src/list/selection.dart';
export 'src/list/sortable.dart';

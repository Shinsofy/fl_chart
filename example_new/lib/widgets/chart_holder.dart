import 'package:example_new/resources/app_dimens.dart';
import 'package:example_new/resources/app_resources.dart';
import 'package:example_new/samples/chart_sample.dart';
import 'package:flutter/material.dart';

class ChartHolder extends StatelessWidget {
  final ChartSample chartSample;

  const ChartHolder({
    Key? key,
    required this.chartSample,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.itemsBackground,
        borderRadius:
            BorderRadius.all(Radius.circular(AppDimens.defaultRadius)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chartSample.name,
            style: const TextStyle(
              color: AppColors.mainTextColor,
            ),
          ),
          chartSample.builder(context),
        ],
      ),
    );
  }
}
